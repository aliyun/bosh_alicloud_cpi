#!/usr/bin/env bash

set -e

bosh_cli=$(realpath bosh-cli/bosh-cli-*)
chmod +x $bosh_cli
cp "${bosh_cli}" /usr/local/bin/bosh2

source director-state/director.env

# CREATE TEST RELEASE
pushd bosh-cpi-src/ci/assets/e2e-test-release
  time bosh2 -n create-release --force --name e2e-test --version 1.0.0
  time bosh2 -n upload-release
popd

# UPLOAD STEMCELL
time bosh2 -n upload-stemcell "$(realpath stemcell/*.tgz)"
time bosh2 -n upload-stemcell "$(realpath heavy-stemcell/*.tgz)"

stemcell_name="$( bosh2 int <( tar xfO $(realpath stemcell/*.tgz) stemcell.MF ) --path /name )"
heavy_stemcell_name="$( bosh2 int <( tar xfO $(realpath heavy-stemcell/*.tgz) stemcell.MF ) --path /name )"
# alicloud_kms_key_arn="$(cat terraform-metadata/metadata | jq --raw-output ".alicloud_kms_key_arn")"

# --cloud-properties "{\"encrypted\": true, \"kms_key_arn\": \"${alicloud_kms_key_arn}\"}" \
time bosh2 repack-stemcell \
  --name e2e-encrypted-heavy-stemcell \
  --version 0.1 \
  "$(realpath heavy-stemcell/*.tgz)" \
  /tmp/e2e-encrypted-heavy-stemcell.tgz
time bosh2 -n upload-stemcell /tmp/e2e-encrypted-heavy-stemcell.tgz
encrypted_heavy_stemcell_img_id="$( bosh2 stemcells | grep e2e-encrypted-heavy-stemcell | awk '{print $NF;}' )"

UPDATE CLOUD CONFIG
time bosh2 -n ucc \
  -l terraform-metadata/metadata \
  bosh-cpi-src/ci/assets/e2e-test-release/cloud-config.yml

# BOSH DEPLOY
time bosh2 -n deploy -d e2e-test \
  -v "stemcell_name=${stemcell_name}" \
  -v "heavy_stemcell_name=${heavy_stemcell_name}" \
  -v "encrypted_heavy_stemcell_img_id=${encrypted_heavy_stemcell_img_id}" \
  -l terraform-metadata/metadata \
  bosh-cpi-src/ci/assets/e2e-test-release/manifest.yml

# RUN ERRANDS
#time bosh2 -n run-errand -d e2e-test iam-instance-profile-test
#time bosh2 -n run-errand -d e2e-test raw-ephemeral-disk-test
time bosh2 -n run-errand -d e2e-test slb-registration-test
#time bosh2 -n run-errand -d e2e-test heavy-stemcell-test
#time bosh2 -n run-errand -d e2e-test encrypted-heavy-stemcell-test