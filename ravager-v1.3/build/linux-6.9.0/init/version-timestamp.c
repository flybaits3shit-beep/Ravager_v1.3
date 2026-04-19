// SPDX-License-Identifier: GPL-2.0-only

#include <generated/compile.h>
#include <generated/utsrelease.h>
#include <linux/proc_ns.h>
#include <linux/refcount.h>
#include <linux/uts.h>
#include <linux/utsname.h>

/*
 * Ravager v1.3 — Dell Latitude 3120 Custom Kernel
 * Rain's Computer Resurrection — Loris, SC
 *
 * This kernel is purpose-built for the Dell Latitude 3120:
 *   CPU:   Intel Celeron N5100 (Jasper Lake / Tremont)
 *   GPU:   Intel UHD Graphics (8086:4e71)
 *   WiFi:  Intel Wi-Fi 6 AX201
 *   NVMe:  KIOXIA BG4 128GB (DRAM-less)
 *   RAM:   4GB LPDDR4x
 */

/*
 * Ravager v1.3 — Dell Latitude 3120 Custom Kernel
 * Rain's Computer Resurrection — Loris, SC
 *
 * This kernel is purpose-built for the Dell Latitude 3120:
 *   CPU:   Intel Celeron N5100 (Jasper Lake / Tremont)
 *   GPU:   Intel UHD Graphics (8086:4e71)
 *   WiFi:  Intel Wi-Fi 6 AX201
 *   NVMe:  KIOXIA BG4 128GB (DRAM-less)
 *   RAM:   4GB LPDDR4x
 */

/*
 * Ravager v1.3 — Dell Latitude 3120 Custom Kernel
 * Rain's Computer Resurrection — Loris, SC
 *
 * This kernel is purpose-built for the Dell Latitude 3120:
 *   CPU:   Intel Celeron N5100 (Jasper Lake / Tremont)
 *   GPU:   Intel UHD Graphics (8086:4e71)
 *   WiFi:  Intel Wi-Fi 6 AX201
 *   NVMe:  KIOXIA BG4 128GB (DRAM-less)
 *   RAM:   4GB LPDDR4x
 */

struct uts_namespace init_uts_ns = {
	.ns.count = REFCOUNT_INIT(2),
	.name = {
		.sysname	= UTS_SYSNAME,
		.nodename	= UTS_NODENAME,
		.release	= UTS_RELEASE,
		.version	= UTS_VERSION,
		.machine	= UTS_MACHINE,
		.domainname	= UTS_DOMAINNAME,
	},
	.user_ns = &init_user_ns,
	.ns.inum = PROC_UTS_INIT_INO,
#ifdef CONFIG_UTS_NS
	.ns.ops = &utsns_operations,
#endif
};

/* FIXED STRINGS! Don't touch! */
const char linux_banner[] =
	"Linux version " UTS_RELEASE " (" LINUX_COMPILE_BY "@"
	LINUX_COMPILE_HOST ") (" LINUX_COMPILER ") " UTS_VERSION "\n";
