# GPU pool guard for shared GB10 / DGX Spark nodes (unified memory): cap each Python process at VES_GPU_POOL_GB.
# Put this directory on PYTHONPATH inside our containers: every Python process that imports torch with CUDA gets
# torch.cuda.set_per_process_memory_fraction(VES_GPU_POOL_GB / total), so the caching allocator raises OOM instead
# of growing past the pool. Only active when VES_GPU_POOL_GB is set.
import os
if os.environ.get("VES_GPU_POOL_GB"):
    try:
        import torch
        if torch.cuda.is_available():
            total = torch.cuda.get_device_properties(0).total_memory
            frac = min(1.0, float(os.environ["VES_GPU_POOL_GB"]) * (1 << 30) / total)
            torch.cuda.set_per_process_memory_fraction(frac, 0)
    except Exception as e:  # never break the interpreter because of the guard
        print(f"[ves-gpu-guard] not applied: {e}")
