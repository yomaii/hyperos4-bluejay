#!/system/bin/sh
# Started by port_esim.rc after boot (root uid, shell domain).
#
# 1. The Xiaomi eSIM manager (com.miui.euicc) refuses to work unless Settings.Secure is_enable_esim_for_user is 1.
#    On Xiaomi phones the "enable eSIM" switch writes it (it also flips a GPIO shared with SIM 2); the Pixel has a
#    dedicated eSIM slot and nothing writes it. The setup wizard loops if it is not 1. Only written when unset.
# 2. Dual SIM: if persist.radio.multisim.config is empty, call ITelephony.switchMultiSimConfig(2) (transaction 240
#    on OS4.0.29.0). config/esim/product.prop already sets dsds, so this is a fallback. If that fails and the physical
#    slot stays ABSENT, map logical slot 0 to physical slot 1 with setSimSlotMapping (176).
#    Transaction numbers come from ITelephony$Stub in framework.jar and change between versions.
TAG=port_esim

esim_flag() {
  i=0
  while [ $i -lt 24 ]; do
    v="$(settings get secure is_enable_esim_for_user 2>&1)"
    log -t $TAG "flag try $i: is_enable_esim_for_user='$v'"
    case "$v" in
      1) log -t $TAG "flag already 1"; return 0 ;;
      ""|null) out="$(settings put secure is_enable_esim_for_user 1 2>&1)"; log -t $TAG "put 1: rc=$? out='$out'" ;;
      0|-1) log -t $TAG "flag set to $v by someone else, leave it"; return 0 ;;
      *) log -t $TAG "settings get failed, retry" ;;
    esac
    i=$((i + 1))
    sleep 5
  done
  log -t $TAG "flag: gave up"
}

dual_sim() {
  m="$(getprop persist.radio.multisim.config)"
  if [ -n "$m" ]; then log -t $TAG "dual: multisim.config='$m', leave it"; return 0; fi
  i=0
  while [ $i -lt 6 ]; do
    out="$(service call phone 240 i32 2 2>&1)"
    sleep 10
    m="$(getprop persist.radio.multisim.config)"
    log -t $TAG "dual try $i: switchMultiSimConfig(2) -> '$out', multisim.config='$m'"
    [ "$m" = dsds ] && return 0
    i=$((i + 1))
  done
  log -t $TAG "dual: gave up"
  return 1
}

esim_slot() {
  absent=0
  i=0
  while [ $i -lt 30 ]; do
    s="$(getprop gsm.sim.state)"
    case "$s" in
      ABSENT) absent=$((absent + 1)) ;;
      ""|NOT_READY|UNKNOWN) absent=0 ;;
      *) log -t $TAG "slot: sim state '$s', nothing to do"; return 0 ;;
    esac
    if [ $absent -ge 3 ]; then
      out="$(service call phone 176 i32 1 i32 1 i32 0 i32 1 i32 0 2>&1)"
      log -t $TAG "slot: physical slot empty, switched logical 0 -> physical 1 (eSIM): $out"
      return 0
    fi
    i=$((i + 1))
    sleep 3
  done
  log -t $TAG "slot: sim state still '$s' after 90s, leave it"
}

# 3. Hide the eSIM master switch in SIM settings: turning it off powers down a Qualcomm modem path that fails here.
#    MiuiEsimManagerBase.isRemoveEsimSwitch() is true with is_enable_esim_by_cota=1.
hide_switch() {
  [ "$(settings get secure is_enable_esim_by_cota)" = 1 ] && return 0
  settings put secure is_enable_esim_by_cota 1
  log -t $TAG "switch: is_enable_esim_by_cota=1 ($(settings get secure is_enable_esim_by_cota))"
}

esim_flag
hide_switch
dual_sim || esim_slot
