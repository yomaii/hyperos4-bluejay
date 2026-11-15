# On screen on, make PortPerfBridge renew immediately. The Pixel hints expire after an hour of real time
# (including sleep) while the 50 minute Handler timer does not run in deep sleep.
#
# Java equivalent:
#   final class PortPerfScreen extends BroadcastReceiver {
#     private final PortPerfBridge mB;
#     PortPerfScreen(PortPerfBridge b) { mB = b; }
#     public void onReceive(Context c, Intent i) { mB.run(); }   // registered with mHandler
#   }

.class final Lcom/android/server/power/PortPerfScreen;
.super Landroid/content/BroadcastReceiver;
.source "PortPerfScreen.java"


# instance fields
.field private final mB:Lcom/android/server/power/PortPerfBridge;


# direct methods
.method constructor <init>(Lcom/android/server/power/PortPerfBridge;)V
    .registers 2

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V

    iput-object p1, p0, Lcom/android/server/power/PortPerfScreen;->mB:Lcom/android/server/power/PortPerfBridge;

    return-void
.end method


# virtual methods
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .registers 4

    iget-object v0, p0, Lcom/android/server/power/PortPerfScreen;->mB:Lcom/android/server/power/PortPerfBridge;

    invoke-virtual {v0}, Lcom/android/server/power/PortPerfBridge;->run()V

    return-void
.end method
