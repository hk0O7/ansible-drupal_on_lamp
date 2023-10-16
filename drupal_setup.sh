#!/usr/bin/env bash
set -euo pipefail

DRUPAL_PORT=${DRUPAL_PORT:=80}
SITE_NAME=${SITE_NAME:='Default Drupal site'}
DRUPAL_USER=${DRUPAL_USER:=drupaladmin}
DRUPAL_PASS=${DRUPAL_PASS:='cH4Ng3_m3!'}
SITE_COUNTRY=CH
SITE_TIMEZONE=Europe/Berlin
MYSQL_DB=drupal
MYSQL_USER=${MYSQL_USER:=drupal}
MYSQL_PASS=${MYSQL_PASS:='d3F4U1t_Dr00p4L_mYsQ1_p455phR4S3'}


headFile=$(mktemp -p /dev/shm)
bodyFile=$(mktemp -p /dev/shm)

echo -n > "$headFile"
echo -n > "$bodyFile"
trap "rm $headFile $bodyFile" EXIT

indent() {
	awk '{print "    " $0}'
}

dcurl() {
	local path="$1"
	shift
	echo ----------
	if (($#)); then echo $path "$@":
	else echo $path:
	fi
	local curlStatus=0
	curl "localhost:$DRUPAL_PORT$path" -s -D "$headFile" -o "$bodyFile" "$@" || curlStatus=$?
	grep -iE '^((HTTP)|(Set-Cookie:)|(Location:))' "$headFile" | indent ||
		echo 'No headers' | indent
	echo ----- | indent
	head -16 "$bodyFile" | indent
	if ((curlStatus)); then exit $curlStatus; fi
}

getFBID() {
	local inputLine=$(grep -E '^<input' "$bodyFile") ||
		echo 'getFBID(): failed to find $inputLine'
	if ! form_build_id=$(
		grep -Eo 'name="form_build_id" value="[^"]+"' <<< "$inputLine" |
		 cut -d'"' -f4
	); then
		echo 'getFBID(): failed to get form_build_id' | indent
		exit 1
	fi
	echo ----- | indent
	echo "getFBID(): form_build_id: $form_build_id" | indent
	if form_id=$(
		grep -Eo 'name="form_id" value="[^"]+"' <<< "$inputLine" |
		 cut -d'"' -f4
	); then
		echo "getFBID(): form_id: $form_id" | indent
	fi
}

validateFID() {
	if [[ "$1" != "$form_id" ]]; then
		echo "validateFID(): Expected form_id \`$1' does not match \`$form_id'."
		exit 1
	fi
}

getCookie() {
	echo ----- | indent
	if cookie=$(
		grep -E '^Set-Cookie: ' "$headFile" |
		 tail -1 |
		 cut -d: -f2 |
		 cut -d';' -f1 |
		 sed -r 's/^\s+//'
	); then
		echo "getCookie(): cookie: $cookie" | indent
	else
		echo 'getCookie(): Failed to find cookie.' | indent
		exit 1
	fi
}

dcurl /core/install.php
if grep -qE '^\s*<title>Drupal already installed' "$bodyFile"; then
	echo; echo 'Drupal site has already been set up; nothing to do.'
	exit 0
fi
getFBID

validateFID install_select_language_form
dcurl /core/install.php -X POST \
  -d form_build_id=$form_build_id \
  -d form_id=install_select_language_form \
  --data-urlencode 'op=Save and continue' \
  -d langcode=en

dcurl /core/install.php?rewrite=ok\&langcode=en
getFBID

validateFID install_select_profile_form
dcurl /core/install.php?rewrite=ok\&langcode=en -X POST \
  -d form_build_id=$form_build_id \
  -d form_id=install_select_profile_form \
  --data-urlencode 'op=Save and continue' \
  -d profile=standard

dcurl /core/install.php?rewrite=ok\&langcode=en\&profile=standard
getFBID

validateFID install_settings_form
dcurl /core/install.php?rewrite=ok\&langcode=en\&profile=standard -X POST \
  -d form_build_id=$form_build_id \
  -d form_id=install_settings_form \
  --data-urlencode 'op=Save and continue' \
  -d driver=mysql \
  --data-urlencode "mysql[database]=$MYSQL_DB" \
  --data-urlencode "mysql[username]=$MYSQL_USER" \
  --data-urlencode "mysql[password]=$MYSQL_PASS" \
  --data-urlencode 'mysql[host]=localhost' \
  --data-urlencode 'mysql[port]=3306' \
  --data-urlencode 'mysql[isolation_level]=READ COMMITTED' \
  --data-urlencode 'mysql[prefix]='
getCookie

dcurl /core/install.php?rewrite=ok\&langcode=en\&profile=standard\&id=1\&op=start \
  -b $cookie # (should start install process)

echo ----------
echo 'Waiting for Drupal to complete the installation process...'
while true; do
	sleep 8
	dcurl \
	  /core/install.php?rewrite=ok\&langcode=en\&profile=standard\&id=1\&op=do_nojs \
	  -b $cookie >/dev/null
	echo
	if ! grep -E '^\s*<div class="progress__((percentage)|(description))"' "$bodyFile"
	then
		echo 'Failed to find progress status.'
		exit 1
	fi
	if grep -qF 'op=finished"' "$bodyFile"; then
		echo; echo 'Drupal has finished the installation process.'
		break
	fi
done

dcurl /core/install.php?rewrite=ok\&langcode=en\&profile=standard\&id=1\&op=finished \
  -b $cookie  # (will cause it to mark cookie as deleted, but also redirect elsewhere)

dcurl /core/install.php?rewrite=ok\&langcode=en\&profile=standard
  # (should return "Configure site" page, no cookies)
getFBID

validateFID install_configure_form
dcurl /core/install.php?rewrite=ok\&langcode=en\&profile=standard -X POST \
  -d form_build_id=$form_build_id \
  -d form_id=install_configure_form \
  --data-urlencode 'op=Save and continue' \
  --data-urlencode "site_name=$SITE_NAME" \
  --data-urlencode 'site_mail=root@localhost' \
  --data-urlencode "account[name]=$DRUPAL_USER" \
  --data-urlencode "account[pass][pass1]=$DRUPAL_PASS" \
  --data-urlencode "account[pass][pass2]=$DRUPAL_PASS" \
  --data-urlencode 'account[mail]=root@localhost' \
  -d "site_default_country=$SITE_COUNTRY" \
  --data-urlencode "date_default_timezone=$SITE_TIMEZONE" \
  -d enable_update_status_module=0 \
  -d enable_update_status_emails=0
  # (should redirect to / and return cookie (irrelevant at this point))

dcurl /
if ! grep -qE '^HTTP[^ ]* 200 OK$' <<< $(tr -d '\r' < "$headFile"); then
	echo 'Setup might not have gone as expected (HTTP 200 not returned at /).'
	exit 1
fi

echo 'Drupal site has been successfully set up.'
exit 0
