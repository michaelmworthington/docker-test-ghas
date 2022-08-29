#!/bin/bash

CURRENT_PDI_UID=`id --user pdi`
CURRENT_PDI_GID=`id --group pdi`

if [ -n "$P_PDI_UID" ] && [ $P_PDI_UID -ne $CURRENT_PDI_UID ]
then
  echo "Updating user PDI with new User ID: $P_PDI_UID"
  usermod --uid $P_PDI_UID -o pdi
else
  echo "Using current PDI User ID: $CURRENT_PDI_UID"
fi

if [ -n "$P_PDI_GID" ] && [ $P_PDI_GID -ne $CURRENT_PDI_GID ]
then
  echo "Updating user PDI with new Group ID: $P_PDI_GID"
  groupmod --gid $P_PDI_GID -o pdi
else
  echo "Using current PDI Group ID: $CURRENT_PDI_GID"
fi

# run the original command as the pdi user as process id 1 so it works with Docker
exec gosu pdi /home/pdi/pentaho/run_job.sh "$@"
