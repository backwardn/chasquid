#!/bin/bash

set -e
. $(dirname ${0})/../util/lib.sh

init

generate_certs_for testserver
add_user testserver user secretpassword
add_user testserver someone secretpassword
add_user testserver blockme secretpassword

mkdir -p .logs
chasquid -v=2 --log_dir=.logs --config_dir=config &
wait_until_ready 1025

cp config/hooks/post-data.good config/hooks/post-data

run_msmtp someone@testserver < content

wait_for_file .mail/someone@testserver

mail_diff content .mail/someone@testserver

if ! grep -q "X-Post-Data: success" .mail/someone@testserver; then
	echo "missing X-Post-Data header"
	exit 1
fi

function check() {
	if ! grep -q "$1" .data/post-data.out; then
		echo missing: $1
		exit 1
	fi
}

# Verify that the environment for the hook was reasonable.
check "RCPT_TO=someone@testserver"
check "MAIL_FROM=user@testserver"
check "USER=$USER"
check "PWD=$PWD/config"
check "FROM_LOCAL_DOMAIN=1"
check "ON_TLS=1"
check "AUTH_AS=user@testserver"
check "PATH="
check "REMOTE_ADDR="


# Check that a failure in the script results in failing delivery.
if run_msmtp blockme@testserver < content 2>/dev/null; then
	echo "ERROR: hook did not block email as expected"
	exit 1
fi

# Check that the bad hooks don't prevent delivery.
for i in config/hooks/post-data.bad*; do
	cp $i config/hooks/post-data

	run_msmtp someone@testserver < content
	wait_for_file .mail/someone@testserver
	mail_diff content .mail/someone@testserver
done

success
