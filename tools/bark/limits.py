"""Keeps the bark tools from taking the whole machine. Import this FIRST (before numba / torch).

BARK_CORES (default 3): the CPU cores used (numba threads, the fit's worker processes, torch threads);
the process also runs at below-normal priority, so the machine stays usable while a fit runs.
Example: `BARK_CORES=2 python bark_perceptual.py fit ...`
"""
import ctypes
import os

CORES = max(int(os.environ.get("BARK_CORES", "3")), 1)
os.environ["NUMBA_NUM_THREADS"] = str(CORES)
os.environ["OMP_NUM_THREADS"] = str(CORES)
os.environ["MKL_NUM_THREADS"] = str(CORES)
try:  # below-normal priority (Windows); elsewhere: nice
    if os.name == "nt":
        ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 0x00004000)
    else:
        os.nice(10)
except Exception:  # (a tool must not fail for this)
    pass
