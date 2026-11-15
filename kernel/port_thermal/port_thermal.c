// SPDX-License-Identifier: GPL-2.0
/*
 * port_thermal: provides Xiaomi's /sys/class/thermal/thermal_message/ temperature nodes.
 *
 * On Xiaomi phones mi_thermald writes the body temperature there and system_server reads it in many places
 * (third-party app throttling, thermal brightness, TurboSched, smart charging...). Without it they use defaults.
 *
 * Creates device thermal_message in the thermal class (/sys/devices/virtual/thermal/thermal_message, next to the
 * thermal zones, labelled sysfs_thermal) with:
 *   board_sensor_temp    read-only body temperature (m°C), computed like VIRTUAL-SKIN in the Pixel thermal HAL
 *                        (/vendor/etc/thermal_info_config.json):
 *                          max( 0.7*neutral + 0.3*skin2,
 *                               0.35*neutral + 0.2*skin1 + 0.1*disp + 0.15*skin2 + 0.2*gnss_tcxo,
 *                               0.7*quiet + 0.3*neutral )
 *                        missing zones are skipped; -ENODATA if all are missing.
 *   ambient_sensor_temp  read-only ambient estimate: quiet_therm (the point farthest from heat sources)
 *   mi_thermal_qos_level, boost, balance_mode
 *                        read-write integers, default 0. Written by mi_thermald on Xiaomi; here they only need to be readable.
 * Parameters (/sys/module/port_thermal/parameters/):
 *   board_override       when non-zero, board_sensor_temp returns it (m°C), for testing Xiaomi thermal policies
 *
 * The zones come from vendor_dlkm drivers, which load after this module (vendor_boot): retried every second for 10 min.
 * thermal_zone_get_temp is exported by GKI but missing from the stock symvers; extra.symvers holds its CRC, computed
 * with genksyms from source and checked against known CRCs of other symbols in the same file.
 */
#define pr_fmt(fmt) "port_thermal: " fmt

#include <linux/device.h>
#include <linux/err.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/sysfs.h>
#include <linux/thermal.h>
#include <linux/workqueue.h>

#define RETRY_MS	1000
#define RETRY_MAX	600

enum { Z_NEUTRAL, Z_SKIN1, Z_SKIN2, Z_QUIET, Z_DISP, Z_GNSS, Z_COUNT };

static const char *const zone_names[Z_COUNT] = {
	[Z_NEUTRAL] = "neutral_therm",
	[Z_SKIN1] = "skin_therm1",
	[Z_SKIN2] = "skin_therm2",
	[Z_QUIET] = "quiet_therm",
	[Z_DISP] = "disp_therm",
	[Z_GNSS] = "gnss_tcxo_therm",
};

/* weights in thousandths, summing to 1000 */
struct term { int zone; int coef; };

static const struct term combo_a[] = { { Z_NEUTRAL, 700 }, { Z_SKIN2, 300 } };
static const struct term combo_b[] = {
	{ Z_NEUTRAL, 350 }, { Z_SKIN1, 200 }, { Z_DISP, 100 }, { Z_SKIN2, 150 }, { Z_GNSS, 200 },
};
static const struct term combo_c[] = { { Z_QUIET, 700 }, { Z_NEUTRAL, 300 } };

static struct thermal_zone_device *zones[Z_COUNT];
static DEFINE_MUTEX(pt_lock);
static struct device *pt_dev;
static struct delayed_work pt_work;
static int pt_tries;

static int board_override;
module_param(board_override, int, 0644);
MODULE_PARM_DESC(board_override, "fixed board_sensor_temp in millicelsius (0 = computed)");

static int qos_level, boost, balance_mode;

/* temperature of a zone; error if not registered yet, retried later */
static int zone_temp(int z, int *t)
{
	struct thermal_zone_device *tz;

	mutex_lock(&pt_lock);
	tz = zones[z];
	if (!tz) {
		tz = thermal_zone_get_zone_by_name(zone_names[z]);
		if (IS_ERR(tz))
			tz = NULL;
		zones[z] = tz;
	}
	mutex_unlock(&pt_lock);
	if (!tz)
		return -ENODEV;
	return thermal_zone_get_temp(tz, t);
}

static int weighted(const struct term *tm, int n, int *out)
{
	long long sum = 0;
	int i, t;

	for (i = 0; i < n; i++) {
		if (zone_temp(tm[i].zone, &t))
			return -ENODATA;
		sum += (long long)tm[i].coef * t;
	}
	*out = (int)div_s64(sum, 1000);
	return 0;
}

static int board_temp(int *out)
{
	int v, best = 0, ok = 0;

	if (!weighted(combo_a, ARRAY_SIZE(combo_a), &v)) { best = v; ok = 1; }
	if (!weighted(combo_b, ARRAY_SIZE(combo_b), &v) && (!ok || v > best)) { best = v; ok = 1; }
	if (!weighted(combo_c, ARRAY_SIZE(combo_c), &v) && (!ok || v > best)) { best = v; ok = 1; }
	if (!ok)
		return -ENODATA;
	*out = best;
	return 0;
}

static ssize_t board_sensor_temp_show(struct device *d, struct device_attribute *a, char *buf)
{
	int t, ret;

	if (board_override)
		return sysfs_emit(buf, "%d\n", board_override);
	ret = board_temp(&t);
	return ret ? ret : sysfs_emit(buf, "%d\n", t);
}
static DEVICE_ATTR_RO(board_sensor_temp);

static ssize_t ambient_sensor_temp_show(struct device *d, struct device_attribute *a, char *buf)
{
	int t, ret = zone_temp(Z_QUIET, &t);

	return ret ? ret : sysfs_emit(buf, "%d\n", t);
}
static DEVICE_ATTR_RO(ambient_sensor_temp);

#define INT_ATTR(name, var)							\
static ssize_t name##_show(struct device *d, struct device_attribute *a, char *buf) \
{									\
	return sysfs_emit(buf, "%d\n", READ_ONCE(var));			\
}									\
static ssize_t name##_store(struct device *d, struct device_attribute *a,	\
			    const char *buf, size_t n)			\
{									\
	int v, ret = kstrtoint(buf, 0, &v);				\
									\
	if (ret)							\
		return ret;						\
	WRITE_ONCE(var, v);						\
	return n;							\
}									\
static DEVICE_ATTR_RW(name)

INT_ATTR(mi_thermal_qos_level, qos_level);
INT_ATTR(boost, boost);
INT_ATTR(balance_mode, balance_mode);

static struct attribute *pt_attrs[] = {
	&dev_attr_board_sensor_temp.attr,
	&dev_attr_ambient_sensor_temp.attr,
	&dev_attr_mi_thermal_qos_level.attr,
	&dev_attr_boost.attr,
	&dev_attr_balance_mode.attr,
	NULL,
};
ATTRIBUTE_GROUPS(pt);

/* get the thermal class from any registered zone and create thermal_message under it */
static void pt_try(struct work_struct *w)
{
	struct thermal_zone_device *tz = NULL;
	struct device *dev;
	int i;

	for (i = 0; i < Z_COUNT && !tz; i++) {
		tz = thermal_zone_get_zone_by_name(zone_names[i]);
		if (IS_ERR(tz))
			tz = NULL;
	}
	if (!tz || !tz->device.class) {
		if (++pt_tries < RETRY_MAX)
			schedule_delayed_work(&pt_work, msecs_to_jiffies(RETRY_MS));
		else
			pr_err("no thermal zone after %d s, giving up\n", RETRY_MAX * RETRY_MS / 1000);
		return;
	}
	dev = device_create_with_groups(tz->device.class, NULL, MKDEV(0, 0), NULL, pt_groups,
					"thermal_message");
	if (IS_ERR(dev)) {
		pr_err("device_create failed: %ld\n", PTR_ERR(dev));
		return;
	}
	pt_dev = dev;
	pr_info("created thermal_message (after %d tries, via %s)\n", pt_tries, tz->type);
}

static int __init pt_init(void)
{
	INIT_DELAYED_WORK(&pt_work, pt_try);
	schedule_delayed_work(&pt_work, 0);
	return 0;
}

static void __exit pt_exit(void)
{
	cancel_delayed_work_sync(&pt_work);
	if (pt_dev)
		device_unregister(pt_dev);
}

module_init(pt_init);
module_exit(pt_exit);
MODULE_DESCRIPTION("Xiaomi thermal_message nodes from Pixel thermal zones");
MODULE_LICENSE("GPL");
