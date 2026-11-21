#include "perf_probe_native.h"

#include <godot_cpp/classes/os.hpp>

#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
#else
#include <sys/resource.h>
#endif

using namespace godot;

void PerfProbe::_bind_methods() {
	ClassDB::bind_static_method("PerfProbe", D_METHOD("cpu_seconds"), &PerfProbe::cpu_seconds);
	ClassDB::bind_static_method("PerfProbe", D_METHOD("memory_mb"), &PerfProbe::memory_mb);
	ClassDB::bind_static_method("PerfProbe", D_METHOD("cores"), &PerfProbe::cores);
}

double PerfProbe::cpu_seconds() {
#ifdef _WIN32
	FILETIME created, exited, kernel, user;
	if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user)) {
		return -1.0;
	}
	const double k = (double)(((uint64_t)kernel.dwHighDateTime << 32) | kernel.dwLowDateTime);
	const double u = (double)(((uint64_t)user.dwHighDateTime << 32) | user.dwLowDateTime);
	return (k + u) * 1.0e-7; // (100 ns units)
#else
	struct rusage usage;
	if (getrusage(RUSAGE_SELF, &usage) != 0) {
		return -1.0;
	}
	return (double)usage.ru_utime.tv_sec + usage.ru_utime.tv_usec * 1.0e-6 + (double)usage.ru_stime.tv_sec + usage.ru_stime.tv_usec * 1.0e-6;
#endif
}

double PerfProbe::memory_mb() {
#ifdef _WIN32
	PROCESS_MEMORY_COUNTERS counters;
	if (!GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters))) {
		return -1.0;
	}
	return (double)counters.WorkingSetSize / 1048576.0;
#else
	struct rusage usage;
	if (getrusage(RUSAGE_SELF, &usage) != 0) {
		return -1.0;
	}
#ifdef __APPLE__
	return (double)usage.ru_maxrss / 1048576.0; // (bytes)
#else
	return (double)usage.ru_maxrss / 1024.0; // (kilobytes; the peak)
#endif
#endif
}

int PerfProbe::cores() {
	return OS::get_singleton()->get_processor_count();
}
