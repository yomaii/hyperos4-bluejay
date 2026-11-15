.class final Lcom/android/server/port/PortGestures$L;
.super Landroid/hardware/TriggerEventListener;
.source "PortGestures.java"

# Sensor callback for PortGestures: type 1 = tap, 2 = long press on the fingerprint area.


# instance fields
.field private final mOwner:Lcom/android/server/port/PortGestures;

.field private final mType:I


# direct methods
.method constructor <init>(Lcom/android/server/port/PortGestures;I)V
    .registers 3

    invoke-direct {p0}, Landroid/hardware/TriggerEventListener;-><init>()V

    iput-object p1, p0, Lcom/android/server/port/PortGestures$L;->mOwner:Lcom/android/server/port/PortGestures;

    iput p2, p0, Lcom/android/server/port/PortGestures$L;->mType:I

    return-void
.end method


# virtual methods
.method public onTrigger(Landroid/hardware/TriggerEvent;)V
    .registers 4

    iget-object v0, p0, Lcom/android/server/port/PortGestures$L;->mOwner:Lcom/android/server/port/PortGestures;

    iget v1, p0, Lcom/android/server/port/PortGestures$L;->mType:I

    invoke-virtual {v0, v1}, Lcom/android/server/port/PortGestures;->onTrigger(I)V

    return-void
.end method
