sed -i -e 's/"xdm"/"slim"/' /etc/conf.d/xdm
sed -i -e 's/#default_user        simone/default_user        pierre/g' /etc/slim.conf
sed -i -e 's/current_theme       default/current_theme       slim-gentoo-simple/g' /etc/slim.conf
sed -i -e 's/#focus_password      no/focus_password      yes/g' /etc/slim.conf
