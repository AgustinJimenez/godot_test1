#pragma once

// PerfProbe (task 101): what the process costs the machine, for the debug overlay (HUD "Detailed performance").
// cpu_seconds(): the CPU time this process has used so far (all threads, user + kernel), -1 where unknown; its change over the wall time, over the
// logical cores, is the CPU load. memory_mb(): the working set (RAM the process holds), -1 where unknown. cores(): logical processors.

#include <godot_cpp/classes/object.hpp>

namespace godot {

class PerfProbe : public Object {
	GDCLASS(PerfProbe, Object)

protected:
	static void _bind_methods();

public:
	static double cpu_seconds();
	static double memory_mb();
	static int cores();
};

} // namespace godot
