#!/bin/bash

LC_ALL=en_US.UTF-8

log "tune postgresql configuration file, 4 GB memory"
gsed -i \
  -e "s/max_connections = .*/max_connections = 200/" \
  -e "s/shared_buffers = .*/shared_buffers = 1GB/" \
  -e "s/#*maintenance_work_mem = .*/maintenance_work_mem = 256MB/" \
  -e "s/#*work_mem = .*/work_mem = 1310kB/" \
  -e "s/#*effective_cache_size = .*/effective_cache_size = 3GB/" \
  -e "s/#*checkpoint_completion_target = .*/checkpoint_completion_target = 0.9/" \
  /var/pgsql/data/postgresql.conf

log "enable postgresql service"
svcadm enable -s svc:/pkgsrc/postgresql:default

log "waiting for the socket to show up"
COUNT="0"
while ! ls /tmp/.s.PGSQL.* > /dev/null 2>&1; do
  sleep 1
  ((COUNT = COUNT + 1))
  if [[ $COUNT -eq 60 ]]; then
    log "ERROR Could not talk to PGSQL after 60 seconds"
    ERROR=yes
    break 1
  fi
done
[[ -n "${ERROR}" ]] && exit 31
log "(it took ${COUNT} seconds to start properly)"

log "create new postgres password and update database credentials"
if PGSQL_PW=$(/opt/core/bin/mdata-create-password.sh -m pgsql_pw 2> /dev/null); then
  PGPASSWORD=postgres \
    psql -U postgres -d postgres -c "alter user postgres with password '${PGSQL_PW}';"
fi

log "create user and database for mastodon"
if ! psql -U postgres -lqt | cut -d \| -f 1 | grep -qw mastodon 2> /dev/null; then
  PGPASSWORD=$(mdata-get pgsql_pw)
  export PGPASSWORD
  createuser -U postgres -s mastodon
  createdb mastodon -U postgres -O mastodon \
    --encoding=UTF8 --locale=C --template=template0

  if USER_PGSQL_PW=$(/opt/core/bin/mdata-create-password.sh -m mastodon_pgsql_pw 2> /dev/null); then
    psql -U mastodon -d mastodon -c "alter user postgres with password '${USER_PGSQL_PW}';"
  fi
fi

