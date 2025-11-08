import kopf
import logging
import os
from kubernetes import client, config
from typing import Any, Dict, List
from datetime import datetime, timezone
from collections import deque

logger = logging.getLogger(__name__)

v1 = None
custom_api = None
metrics_api = None
history_buffer: Dict[str, deque] = {}
BUFFER_SIZE = 100


def init_k8s_clients():
    global v1, custom_api, metrics_api
    try:
        config.load_incluster_config()
        logger.info("Loaded in-cluster config")
    except config.ConfigException:
        config.load_kube_config()
        logger.info("Loaded local kubeconfig")
    
    v1 = client.CoreV1Api()
    custom_api = client.CustomObjectsApi()
    metrics_api = client.CustomObjectsApi()


@kopf.on.startup()
def configure(settings: kopf.OperatorSettings, **_):
    settings.posting.level = logging.INFO
    init_k8s_clients()


@kopf.on.create('monitoring.kuberic.io', 'v1', 'clusterutilizations')
def create_fn(spec, name, namespace, logger, **kwargs):
    logger.info(f"ClusterUtilization {name} created")


@kopf.timer('monitoring.kuberic.io', 'v1', 'clusterutilizations', interval=60, initial_delay=5)
def scrape_metrics(spec, name, namespace, status, logger, patch, **kwargs):
    interval = spec.get('scrapeIntervalSeconds', 60)
    cpu_threshold = spec.get('thresholds', {}).get('cpu', 80)
    mem_threshold = spec.get('thresholds', {}).get('memory', 85)
    
    try:
        nodes = v1.list_node().items
        total_cpu_allocatable = 0
        total_mem_allocatable = 0
        
        for node in nodes:
            cpu_str = node.status.allocatable.get('cpu', '0')
            mem_str = node.status.allocatable.get('memory', '0Ki')
            
            total_cpu_allocatable += parse_cpu(cpu_str)
            total_mem_allocatable += parse_memory(mem_str)
        
        used_cpu = 0
        used_mem = 0
        namespace_usage: Dict[str, float] = {}
        
        try:
            pod_metrics = metrics_api.list_cluster_custom_object(
                group="metrics.k8s.io",
                version="v1beta1",
                plural="pods"
            )
            
            for pod in pod_metrics.get('items', []):
                pod_ns = pod['metadata'].get('namespace', 'unknown')
                for container in pod.get('containers', []):
                    cpu_usage = parse_cpu(container['usage'].get('cpu', '0'))
                    mem_usage = parse_memory(container['usage'].get('memory', '0Ki'))
                    used_cpu += cpu_usage
                    used_mem += mem_usage
                    namespace_usage[pod_ns] = namespace_usage.get(pod_ns, 0) + cpu_usage
        except Exception as e:
            logger.warning(f"Metrics API unavailable: {e}")
        
        cpu_pct = (used_cpu / total_cpu_allocatable * 100) if total_cpu_allocatable > 0 else 0
        mem_pct = (used_mem / total_mem_allocatable * 100) if total_mem_allocatable > 0 else 0
        
        if name not in history_buffer:
            history_buffer[name] = deque(maxlen=BUFFER_SIZE)
        history_buffer[name].append({'cpu': cpu_pct, 'mem': mem_pct})
        
        cpu_values = sorted([h['cpu'] for h in history_buffer[name]])
        mem_values = sorted([h['mem'] for h in history_buffer[name]])
        
        cpu_p50 = percentile(cpu_values, 50)
        cpu_p90 = percentile(cpu_values, 90)
        cpu_p95 = percentile(cpu_values, 95)
        mem_p50 = percentile(mem_values, 50)
        mem_p90 = percentile(mem_values, 90)
        mem_p95 = percentile(mem_values, 95)
        
        top_ns = sorted(namespace_usage.items(), key=lambda x: x[1], reverse=True)[:5]
        top_namespaces = [{'namespace': ns, 'cpuMillicores': int(usage * 1000)} for ns, usage in top_ns]
        
        pods = v1.list_pod_for_all_namespaces()
        pending_count = sum(1 for p in pods.items if p.status.phase == 'Pending')
        
        timestamp = datetime.now(timezone.utc).isoformat()
        
        recommendations = []
        if cpu_pct > cpu_threshold:
            recommendations.append(f"CPU usage ({cpu_pct:.1f}%) exceeds threshold ({cpu_threshold}%)")
        if mem_pct > mem_threshold:
            recommendations.append(f"Memory usage ({mem_pct:.1f}%) exceeds threshold ({mem_threshold}%)")
        
        logger.info(f"kuberic: cpu={cpu_pct:.1f}% p90={cpu_p90:.1f}% mem={mem_pct:.1f}% pods={len(pods.items)}")
        
        # Update status directly via patch - use update() method not assignment
        patch.status.update({
            'summary': {
                'cpuPercent': round(cpu_pct, 2),
                'memoryPercent': round(mem_pct, 2)
            },
            'percentiles': {
                'cpu': {'p50': round(cpu_p50, 2), 'p90': round(cpu_p90, 2), 'p95': round(cpu_p95, 2)},
                'memory': {'p50': round(mem_p50, 2), 'p90': round(mem_p90, 2), 'p95': round(mem_p95, 2)}
            },
            'topNamespaces': top_namespaces,
            'saturation': {
                'pendingPods': pending_count,
                'unschedulablePods': 0
            },
            'timestamp': timestamp,
            'recommendations': recommendations
        })
        
    except Exception as e:
        logger.error(f"Error scraping metrics: {e}", exc_info=True)


def parse_cpu(cpu_str: str) -> float:
    if cpu_str.endswith('m'):
        return float(cpu_str[:-1]) / 1000
    elif cpu_str.endswith('n'):
        return float(cpu_str[:-1]) / 1_000_000_000
    return float(cpu_str)


def parse_memory(mem_str: str) -> float:
    units = {'Ki': 1024, 'Mi': 1024**2, 'Gi': 1024**3, 'Ti': 1024**4,
             'K': 1000, 'M': 1000**2, 'G': 1000**3, 'T': 1000**4}
    for suffix, multiplier in units.items():
        if mem_str.endswith(suffix):
            return float(mem_str[:-len(suffix)]) * multiplier
    return float(mem_str)


def percentile(values: List[float], pct: int) -> float:
    if not values:
        return 0.0
    idx = int(len(values) * pct / 100)
    idx = min(idx, len(values) - 1)
    return values[idx]

