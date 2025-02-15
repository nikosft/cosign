#!/usr/bin/env bash
#
# Copyright 2021 The Sigstore Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

echo "copying rekor repo"
pushd $HOME
if [[ ! -d rekor ]]; then
   git clone https://github.com/sigstore/rekor.git
else
   pushd rekor
   git pull
   popd
fi
cd rekor

echo "starting services"
docker-compose up -d

count=0

echo -n "waiting up to 60 sec for system to start"
until [ $(docker-compose ps | grep -c "(healthy)") == 3 ];
do
    if [ $count -eq 6 ]; then
       echo "! timeout reached"
       exit 1
    else
       echo -n "."
       sleep 10
       let 'count+=1'
    fi
done

echo
echo "running tests"

popd
go build -o cosign ./cmd/cosign
go test -timeout 15m -tags=e2e -race $(go list ./... | grep -v third_party/)

# Test `cosign dockerfile verify`
./cosign dockerfile verify ./test/testdata/single_stage.Dockerfile --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com
if (./cosign dockerfile verify ./test/testdata/unsigned_build_stage.Dockerfile --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com); then false; fi
./cosign dockerfile verify --base-image-only ./test/testdata/unsigned_build_stage.Dockerfile --certificate-identity https://github.com/distroless/static/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com
./cosign dockerfile verify ./test/testdata/fancy_from.Dockerfile --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com
test_image="ghcr.io/distroless/alpine-base" ./cosign dockerfile verify ./test/testdata/with_arg.Dockerfile  --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com
# Image exists, but is unsigned
if (test_image="ubuntu" ./cosign dockerfile verify ./test/testdata/with_arg.Dockerfile  --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com); then false; fi
./cosign dockerfile verify ./test/testdata/with_lowercase.Dockerfile  --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com

# Test `cosign manifest verify`
./cosign manifest verify ./test/testdata/signed_manifest.yaml --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com
if (./cosign manifest verify ./test/testdata/unsigned_manifest.yaml --certificate-identity https://github.com/distroless/alpine-base/.github/workflows/release.yaml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com); then false; fi

# Run the built container to make sure it doesn't crash
make ko-local
img="ko.local/cosign:$(git rev-parse HEAD)"
docker run $img version

echo "cleanup"
cd $HOME/rekor
docker-compose down
