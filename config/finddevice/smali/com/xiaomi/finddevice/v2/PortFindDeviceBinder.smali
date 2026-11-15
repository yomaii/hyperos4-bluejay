.class public Lcom/xiaomi/finddevice/v2/PortFindDeviceBinder;
.super Landroid/os/Binder;
.source "PortFindDevice"

# Binder of the Find Device stub.
#
# The real Find Device app is removed (it hangs the setup wizard). Xiaomi Account (also when updated in /data/app)
# throws a RuntimeException in miui.cloud.finddevice.FindDeviceStatusManager when it cannot bind
# com.xiaomi.finddevice/.v2.FindDeviceStatusManagerService.
#
# Interface miui.cloud.finddevice.IFindDeviceStatusManagerAsync: data = token + args (callback binder),
# reply = no exception + int; the client treats int != 0 as "out of service" (a RemoteException callers catch).
#   transaction 1 getFindDeviceInfo(IFindDeviceInfoCallback): send a FindDeviceInfo (off, unlocked, empty strings)
#          through the callback, then reply 0. The client waits on an XDataLatch, so the callback goes first.
#   all other transactions: reply 1.
# Callback miui.cloud.finddevice.IFindDeviceInfoCallback transaction 1 onData (oneway):
#   token + int 1 (non-null) + FindDeviceInfo{int isOpen, int isLocked, sessionUserId, displayId, fid, email, phone, findToken}

.method public constructor <init>()V
    .registers 3

    invoke-direct {p0}, Landroid/os/Binder;-><init>()V

    const/4 v0, 0x0

    const-string v1, "miui.cloud.finddevice.IFindDeviceStatusManagerAsync"

    invoke-virtual {p0, v0, v1}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V

    return-void
.end method

.method protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
    .registers 9

    const/4 v0, 0x1

    if-lt p1, v0, :call_super

    const v1, 0xffffff

    if-gt p1, v1, :call_super

    # v2 = int returned to the client, default 1 (out of service)
    const/4 v2, 0x1

    if-ne p1, v0, :write_reply

    const-string v1, "miui.cloud.finddevice.IFindDeviceStatusManagerAsync"

    invoke-virtual {p2, v1}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V

    invoke-virtual {p2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;

    move-result-object v1

    if-eqz v1, :write_reply

    invoke-static {v1}, Lcom/xiaomi/finddevice/v2/PortFindDeviceBinder;->sendInfo(Landroid/os/IBinder;)Z

    move-result v3

    if-eqz v3, :write_reply

    const/4 v2, 0x0

    :write_reply
    if-eqz p3, :done

    invoke-virtual {p3}, Landroid/os/Parcel;->writeNoException()V

    invoke-virtual {p3, v2}, Landroid/os/Parcel;->writeInt(I)V

    :done
    return v0

    :call_super
    invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z

    move-result v0

    return v0
.end method

# Send "Find Device off" through the callback; true on success
.method private static sendInfo(Landroid/os/IBinder;)Z
    .registers 6

    invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;

    move-result-object v0

    :try_start
    const-string v1, "miui.cloud.finddevice.IFindDeviceInfoCallback"

    invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V

    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V

    const/4 v2, 0x0

    invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V

    invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V

    const/4 v3, 0x0

    invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V

    invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V

    invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V

    invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V

    invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V

    invoke-virtual {v0, v3}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V

    const/4 v4, 0x0

    # transaction 1, FLAG_ONEWAY = 1
    invoke-interface {p0, v1, v0, v4, v1}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
    :try_end
    .catch Ljava/lang/Exception; {:try_start .. :try_end} :catch_all

    invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V

    return v1

    :catch_all
    move-exception v1

    const-string v2, "PortFindDevice"

    const-string v3, "onData failed"

    invoke-static {v2, v3, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V

    const/4 v1, 0x0

    return v1
.end method
