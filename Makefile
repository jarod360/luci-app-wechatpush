include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wechatpush
PKG_VERSION:=3.6.14
PKG_RELEASE:=2

LUCI_MAINTAINER:=tty228 <tty228@yeah.net>
PKG_CONFIG_DEPENDS:= \
        CONFIG_PACKAGE_$(PKG_NAME)_Enable_Traffic_Monitoring \
        CONFIG_PACKAGE_$(PKG_NAME)_Enable_Local_Disk_Information_Detection \
        CONFIG_PACKAGE_$(PKG_NAME)_Enable_Host_Information_Detection

LUCI_TITLE:=LuCI support for wechatpush
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+iputils-arping +curl +jq +bash +luci-lua-runtime \
        +PACKAGE_$(PKG_NAME)_Enable_Traffic_Monitoring:wrtbwmon \
        +PACKAGE_$(PKG_NAME)_Enable_Local_Disk_Information_Detection:lsblk \
        +PACKAGE_$(PKG_NAME)_Enable_Local_Disk_Information_Detection:smartmontools \
        +PACKAGE_$(PKG_NAME)_Enable_Local_Disk_Information_Detection:smartmontools-drivedb \
        +PACKAGE_$(PKG_NAME)_Enable_Host_Information_Detection:openssh-client \
        +PACKAGE_$(PKG_NAME)_Enable_Host_Information_Detection:openssh-keygen

define Package/$(PKG_NAME)/config
config PACKAGE_$(PKG_NAME)_Enable_Traffic_Monitoring
        bool "Enable Traffic Monitoring"
        help
                The traffic statistics feature relies on the wrtbwmon package. This plugin may conflict with Routing/NAT, Flow Offloading, and proxy internet access plugins, potentially leading to an inability to retrieve traffic information.
        select PACKAGE_wrtbwmon
        depends on PACKAGE_$(PKG_NAME)
        default n
config PACKAGE_$(PKG_NAME)_Enable_Local_Disk_Information_Detection
        bool "Local Disk Information Detection"
        help
                If the lsblk package is not installed, the total disk capacity information might be inconsistent with actual values. When smartctl is not installed, information about disk temperature, power-on time, health status, and more will be unavailable. If you are using a virtual machine or have not installed a physical disk, this feature is typically unnecessary.
        select PACKAGE_lsblk
        select PACKAGE_smartmontools
        select PACKAGE_smartmontools-drivedb
        depends on PACKAGE_$(PKG_NAME)
        default n
config PACKAGE_$(PKG_NAME)_Enable_Host_Information_Detection
        bool "Host Information Detection"
        help
                When using a virtual machine and requiring information about the host machine's temperature and disk details, you need to install openssh-client and openssh-keygen for SSH connections.
        select PACKAGE_openssh-client
        select PACKAGE_openssh-keygen
        depends on PACKAGE_$(PKG_NAME)
        default n
endef

# Keep only the main UCI configuration when the package is removed.
define Package/$(PKG_NAME)/conffiles
/etc/config/wechatpush
endef

# Remove runtime state created by the application before opkg removes package files.
# OpenWrt's default_prerm invokes this hook from prerm-pkg, then disables/stops
# every init script owned by this package.
define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ "$${PKG_UPGRADE}" = "1" ] && exit 0

# default_prerm already disables and stops this package's init script.
# Preserve unrelated root crontab jobs.
if command -v crontab >/dev/null 2>&1; then
	old_crontab=$$(crontab -l 2>/dev/null || true)
	new_crontab=$$(printf '%s\n' "$$old_crontab" | grep -Fv \
		-e '/usr/share/wechatpush/wechatpush' \
		-e '/tmp/wechatpush/' || true)

	if [ "$$old_crontab" != "$$new_crontab" ]; then
		if [ -n "$$new_crontab" ]; then
			printf '%s\n' "$$new_crontab" | crontab - 2>/dev/null || true
		else
			crontab -r 2>/dev/null || true
		fi
		[ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1 || true
	fi
fi

# Remove runtime state, preserving /etc/config/wechatpush.
rm -rf /tmp/wechatpush
rm -f /usr/share/wechatpush/errlog /usr/share/wechatpush/autoreboot_count

# Clear non-persistent firewall rules created by the plugin.
[ -x /etc/init.d/firewall ] && /etc/init.d/firewall reload >/dev/null 2>&1 || true

# Invalidate LuCI and rpcd caches.
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache
killall -HUP rpcd 2>/dev/null || true
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
