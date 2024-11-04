while [ -z "$(getprop sys.boot_completed)" ]; do
	sleep 40
done

# Wait until all thermal services up and running
sleep 50

# $1:value $2:filepaths
lock_val() {
	for p in $2; do
		if [ -f "$p" ]; then
			chown root:root "$p"
			chmod 644 "$p"
			echo "$1" >"$p"
			chmod 444 "$p"
		fi
	done
}

list_thermal_services() {
	for rc in /system/etc/init/* /vendor/etc/init/* /odm/etc/init/*; do
		grep -r "^service" "$rc" | awk '{print $2}'
	done | grep thermal
}

list_thermal_proc() {
	ps -e -o comm= | grep thermal
}

for svc in $(list_thermal_services); do
	echo "Stopping $svc"
	stop $svc
done

for proc in $(list_thermal_proc); do
	echo "Freeze $proc"
	kill -SIGSTOP "$(pidof "$proc")"
done

for prop in $(resetprop | grep 'thermal.*running' | awk -F '[][]' '{print $2}'); do
	resetprop $prop freezed
done

if [ -f /proc/driver/thermal/tzcpu ]; then
	t_limit="125" # 125 Celcius
	no_cooler="0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler"
	lock_val "1 ${t_limit}000 0 mtktscpu-sysrst $no_cooler 200" /proc/driver/thermal/tzcpu
	lock_val "1 ${t_limit}000 0 mtktspmic-sysrst $no_cooler 1000" /proc/driver/thermal/tzpmic
	lock_val "1 ${t_limit}000 0 mtktsbattery-sysrst $no_cooler 1000" /proc/driver/thermal/tzbattery
	lock_val "1 ${t_limit}000 0 mtk-cl-kshutdown00 $no_cooler 2000" /proc/driver/thermal/tzpa
	lock_val "1 ${t_limit}000 0 mtktscharger-sysrst $no_cooler 2000" /proc/driver/thermal/tzcharger
	lock_val "1 ${t_limit}000 0 mtktswmt-sysrst $no_cooler 1000" /proc/driver/thermal/tzwmt
	lock_val "1 ${t_limit}000 0 mtktsAP-sysrst $no_cooler 1000" /proc/driver/thermal/tzbts
	lock_val "1 ${t_limit}000 0 mtk-cl-kshutdown01 $no_cooler 1000" /proc/driver/thermal/tzbtsnrpa
	lock_val "1 ${t_limit}000 0 mtk-cl-kshutdown02 $no_cooler 1000" /proc/driver/thermal/tzbtspa
	echo "Remove MediaTek's thermal driver limit"
fi

for trip_point in /sys/class/thermal/*/trip_point_0_temp; do
	lock_val 125000 $trip_point
done

if [ -f /sys/devices/virtual/thermal/thermal_message/cpu_limits ]; then
	echo "Remove Mediatek's CPU limits"
	for i in 0 2 4 6 7; do
		maxfreq="$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq)"
		[ "$maxfreq" -gt "0" ] && lock_val "cpu$i $maxfreq" /sys/devices/virtual/thermal/thermal_message/cpu_limits
	done
fi

if [ -d /proc/ppm ]; then
	echo "Disable thermal-related PPM policies"
	for idx in $(cat /proc/ppm/policy_status | grep -E 'PWR_THRO|THERMAL' | awk -F'[][]' '{print $2}'); do
		lock_val "$idx 0" /proc/ppm/policy_status
	done
fi

if [ -f "/proc/gpufreq/gpufreq_power_limited" ]; then
	lock_val "ignore_batt_oc 1" /proc/gpufreq/gpufreq_power_limited
	lock_val "ignore_batt_percent 1" /proc/gpufreq/gpufreq_power_limited
	lock_val "ignore_low_batt 1" /proc/gpufreq/gpufreq_power_limited
	lock_val "ignore_thermal_protect 1" /proc/gpufreq/gpufreq_power_limited
	lock_val "ignore_pbm_limited 1" /proc/gpufreq/gpufreq_power_limited
fi

lock_val 0 /sys/kernel/msm_thermal/enabled
lock_val "N" /sys/module/msm_thermal/parameters/enabled
lock_val 0 /sys/class/kgsl/kgsl-3d0/throttling
lock_val "stop 1" /proc/mtk_batoc_throttling/battery_oc_protect_stop