// SPDX-License-Identifier: GPL-2.0-only
/*
 * Lenovo ThinkPad X1 Fold (Gen 1) keyboard dock detection.
 *
 * The firmware describes a "Lenovo Device Dock" ACPI device (_HID LEN009E,
 * \_SB.DEVD) that reports whether the magnetic keyboard rests on the lower
 * half of the folding panel:
 *
 *   GDST()  -> Integer, 1 = keyboard docked on the screen, 0 = not docked
 *   GDSZ()  -> Package { x, y, width, height }: the panel area (in native
 *              panel pixels) covered by a docked keyboard
 *
 * The firmware calls Notify(\_SB.DEVD, 0x01) whenever the dock state changes
 * (the state itself comes from the ECLite firmware on the ISH, so the
 * intel_ishtp_eclite driver must be bound for GDST to return fresh data).
 *
 * The state is exposed through sysfs on the platform device:
 *   keyboard_docked  "0" / "1"            (pollable, KOBJ_CHANGE on change)
 *   occlusion        "x y width height"
 */

#include <linux/acpi.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/sysfs.h>

struct fold_dock {
	struct device *dev;
	struct acpi_device *adev;
	struct mutex lock;	/* protects docked */
	int docked;
	u32 occl[4];
	bool have_occl;
};

static int fold_dock_eval_gdst(struct fold_dock *fd, int *docked)
{
	unsigned long long val;
	acpi_status status;

	status = acpi_evaluate_integer(fd->adev->handle, "GDST", NULL, &val);
	if (ACPI_FAILURE(status)) {
		dev_warn(fd->dev, "GDST evaluation failed: %s\n",
			 acpi_format_exception(status));
		return -EIO;
	}
	*docked = !!val;
	return 0;
}

static int fold_dock_eval_gdsz(struct fold_dock *fd)
{
	struct acpi_buffer buf = { ACPI_ALLOCATE_BUFFER, NULL };
	union acpi_object *obj;
	acpi_status status;
	int i, ret = 0;

	status = acpi_evaluate_object(fd->adev->handle, "GDSZ", NULL, &buf);
	if (ACPI_FAILURE(status))
		return -ENODEV;

	obj = buf.pointer;
	if (!obj || obj->type != ACPI_TYPE_PACKAGE || obj->package.count != 4) {
		ret = -EINVAL;
		goto out;
	}
	for (i = 0; i < 4; i++) {
		if (obj->package.elements[i].type != ACPI_TYPE_INTEGER) {
			ret = -EINVAL;
			goto out;
		}
		fd->occl[i] = obj->package.elements[i].integer.value;
	}
	fd->have_occl = true;
out:
	kfree(buf.pointer);
	return ret;
}

static void fold_dock_update(struct fold_dock *fd)
{
	int docked, old;

	if (fold_dock_eval_gdst(fd, &docked))
		return;

	mutex_lock(&fd->lock);
	old = fd->docked;
	fd->docked = docked;
	mutex_unlock(&fd->lock);

	if (old != docked) {
		dev_dbg(fd->dev, "keyboard %s\n", docked ? "docked" : "undocked");
		sysfs_notify(&fd->dev->kobj, NULL, "keyboard_docked");
		kobject_uevent(&fd->dev->kobj, KOBJ_CHANGE);
	}
}

static void fold_dock_notify(acpi_handle handle, u32 event, void *data)
{
	struct fold_dock *fd = data;

	/* 0x01 (Device Check) is what the firmware sends; accept 0x80 too. */
	if (event == ACPI_NOTIFY_DEVICE_CHECK || event == 0x80)
		fold_dock_update(fd);
	else
		dev_dbg(fd->dev, "unhandled notify 0x%02x\n", event);
}

static ssize_t keyboard_docked_show(struct device *dev,
				    struct device_attribute *attr, char *buf)
{
	struct fold_dock *fd = dev_get_drvdata(dev);
	int docked;

	/*
	 * Re-read the state so the attribute is correct even if a firmware
	 * notification was missed (e.g. across suspend or before ECLite was
	 * ready). This also emits the change notification if it changed.
	 */
	fold_dock_update(fd);

	mutex_lock(&fd->lock);
	docked = fd->docked;
	mutex_unlock(&fd->lock);

	return sysfs_emit(buf, "%d\n", docked);
}
static DEVICE_ATTR_RO(keyboard_docked);

static ssize_t occlusion_show(struct device *dev,
			      struct device_attribute *attr, char *buf)
{
	struct fold_dock *fd = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%u %u %u %u\n",
			  fd->occl[0], fd->occl[1], fd->occl[2], fd->occl[3]);
}
static DEVICE_ATTR_RO(occlusion);

static struct attribute *fold_dock_attrs[] = {
	&dev_attr_keyboard_docked.attr,
	&dev_attr_occlusion.attr,
	NULL
};

static umode_t fold_dock_attr_visible(struct kobject *kobj,
				      struct attribute *attr, int n)
{
	struct fold_dock *fd = dev_get_drvdata(kobj_to_dev(kobj));

	if (attr == &dev_attr_occlusion.attr && !fd->have_occl)
		return 0;
	return attr->mode;
}

static const struct attribute_group fold_dock_group = {
	.attrs = fold_dock_attrs,
	.is_visible = fold_dock_attr_visible,
};
__ATTRIBUTE_GROUPS(fold_dock);

static int fold_dock_probe(struct platform_device *pdev)
{
	struct fold_dock *fd;
	int ret;

	fd = devm_kzalloc(&pdev->dev, sizeof(*fd), GFP_KERNEL);
	if (!fd)
		return -ENOMEM;

	fd->dev = &pdev->dev;
	fd->adev = ACPI_COMPANION(&pdev->dev);
	if (!fd->adev)
		return -ENODEV;
	if (!acpi_has_method(fd->adev->handle, "GDST"))
		return -ENODEV;

	ret = devm_mutex_init(&pdev->dev, &fd->lock);
	if (ret)
		return ret;

	platform_set_drvdata(pdev, fd);

	if (fold_dock_eval_gdsz(fd))
		dev_info(&pdev->dev, "no usable GDSZ, occlusion unavailable\n");

	ret = fold_dock_eval_gdst(fd, &fd->docked);
	if (ret)
		return ret;

	/*
	 * The firmware uses Notify(DEVD, 0x01), a *system* notification
	 * (< 0x80), so a device-notify-only handler would never see it.
	 */
	ret = devm_acpi_install_notify_handler(&pdev->dev, ACPI_ALL_NOTIFY,
					       fold_dock_notify, fd);
	if (ret)
		return ret;

	dev_info(&pdev->dev, "keyboard %s, occlusion %ux%u+%u+%u\n",
		 fd->docked ? "docked" : "not docked",
		 fd->occl[2], fd->occl[3], fd->occl[0], fd->occl[1]);
	return 0;
}

static int fold_dock_resume(struct device *dev)
{
	/* The keyboard may have been placed or removed while suspended. */
	fold_dock_update(dev_get_drvdata(dev));
	return 0;
}
static DEFINE_SIMPLE_DEV_PM_OPS(fold_dock_pm, NULL, fold_dock_resume);

static const struct acpi_device_id fold_dock_acpi_ids[] = {
	{ "LEN009E" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, fold_dock_acpi_ids);

static struct platform_driver fold_dock_driver = {
	.driver = {
		.name = "lenovo-fold-dock",
		.acpi_match_table = fold_dock_acpi_ids,
		.dev_groups = fold_dock_groups,
		.pm = pm_sleep_ptr(&fold_dock_pm),
	},
	.probe = fold_dock_probe,
};
module_platform_driver(fold_dock_driver);

MODULE_DESCRIPTION("Lenovo ThinkPad X1 Fold keyboard dock detection");
MODULE_LICENSE("GPL");
