.class public Lcom/xiaomi/finddevice/v2/FindDeviceStatusManagerService;
.super Landroid/app/Service;
.source "PortFindDevice"

# Find Device stub: Xiaomi Account and Settings bind this through FindDeviceStatusManager; returns PortFindDeviceBinder.

.method public constructor <init>()V
    .registers 1

    invoke-direct {p0}, Landroid/app/Service;-><init>()V

    return-void
.end method

.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;
    .registers 3

    new-instance v0, Lcom/xiaomi/finddevice/v2/PortFindDeviceBinder;

    invoke-direct {v0}, Lcom/xiaomi/finddevice/v2/PortFindDeviceBinder;-><init>()V

    return-object v0
.end method
