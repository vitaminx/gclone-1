SHELL = bash
# Branch we are working on
BRANCH := $(or $(BUILD_SOURCEBRANCHNAME),$(lastword $(subst /, ,$(GITHUB_REF))),$(shell git rev-parse --abbrev-ref HEAD))
# Tag of the current commit, if any.  If this is not "" then we are building a release
RELEASE_TAG := $(shell git tag -l --points-at HEAD)
# Version of last release (may not be on this branch)
VERSION := $(shell cat VERSION)
# Last tag on this branch
LAST_TAG := $(shell git describe --tags --abbrev=0)
# Next version
NEXT_VERSION := $(shell echo $(VERSION) | awk -F. -v OFS=. '{print $$1,$$2+1,0}')
NEXT_PATCH_VERSION := $(shell echo $(VERSION) | awk -F. -v OFS=. '{print $$1,$$2,$$3+1}')
# If we are working on a release, override branch to master
ifdef RELEASE_TAG
	BRANCH := master
	LAST_TAG := $(shell git describe --abbrev=0 --tags $(VERSION)^)
endif
TAG_BRANCH := .$(BRANCH)
BRANCH_PATH := branch/$(BRANCH)/
# If building HEAD or master then unset TAG_BRANCH and BRANCH_PATH
ifeq ($(subst HEAD,,$(subst master,,$(BRANCH))),)
	TAG_BRANCH :=
	BRANCH_PATH :=
endif
# Make version suffix -beta.NNNN.CCCCCCCC (N=Commit number, C=Commit)
VERSION_SUFFIX := -beta.$(shell git rev-list --count HEAD).$(shell git show --no-patch --no-notes --pretty='%h' HEAD)
# TAG is current version + commit number + commit + branch
TAG := $(VERSION)$(VERSION_SUFFIX)$(TAG_BRANCH)
ifdef RELEASE_TAG
	TAG := $(RELEASE_TAG)
endif
GO_VERSION := $(shell go version)

ifdef GOTAGS
BUILDTAGS=-tags "$(GOTAGS)"
LINTTAGS=--build-tags "$(GOTAGS)"
endif

.PHONY: gclone vars version

gclone:
	go build -v $(BUILDTAGS) $(BUILD_ARGS)
	mkdir -p `go env GOPATH`/bin/
	cp -av gclone`go env GOEXE` `go env GOPATH`/bin/gclone`go env GOEXE`.new
	mv -v `go env GOPATH`/bin/gclone`go env GOEXE`.new `go env GOPATH`/bin/gclone`go env GOEXE`

test_all:

vars:
	@echo SHELL="'$(SHELL)'"
	@echo BRANCH="'$(BRANCH)'"
	@echo TAG="'$(TAG)'"
	@echo VERSION="'$(VERSION)'"
	@echo GO_VERSION="'$(GO_VERSION)'"
# 	@echo BETA_URL="'$(BETA_URL)'"

btest:


version:
	@echo '$(TAG)'

# Full suite of integration tests
test:	gclone test_all
	-test_all 2>&1 | tee test_all.log
	@echo "Written logs in test_all.log"

# Quick test
quicktest:
	RCLONE_CONFIG="/notfound" go test $(BUILDTAGS) ./...

racequicktest:
	RCLONE_CONFIG="/notfound" go test $(BUILDTAGS) -cpu=2 -race ./...

# Do source code quality checks
check:	gclone
	@echo "-- START CODE QUALITY REPORT -------------------------------"
	@golangci-lint run $(LINTTAGS) ./...
	@echo "-- END CODE QUALITY REPORT ---------------------------------"

# Get the build dependencies
build_dep:
	go run bin/get-github-release.go -extract golangci-lint golangci/golangci-lint 'golangci-lint-.*\.tar\.gz'

# Get the release dependencies we only install on linux
release_dep_linux:
	go run bin/get-github-release.go -extract nfpm goreleaser/nfpm 'nfpm_.*_Linux_x86_64\.tar\.gz'

# Get the release dependencies we only install on Windows
release_dep_windows:
	GO111MODULE=off GOOS="" GOARCH="" go get github.com/josephspurrier/goversioninfo/cmd/goversioninfo

# Update dependencies
showupdates:
	@echo "*** Direct dependencies that could be updated ***"
	@GO111MODULE=on go list -u -f '{{if (and (not (or .Main .Indirect)) .Update)}}{{.Path}}: {{.Version}} -> {{.Update.Version}}{{end}}' -m all 2> /dev/null

# Update direct and indirect dependencies and test dependencies
update:
	GO111MODULE=on go get -u -t ./...
	-#GO111MODULE=on go get -d $(go list -m -f '{{if not (or .Main .Indirect)}}{{.Path}}{{end}}' all)
	GO111MODULE=on go mod tidy

# Tidy the module dependencies
tidy:
	GO111MODULE=on go mod tidy

doc:
	@echo "doc part"

install: gclone
	install -d ${DESTDIR}/usr/bin
	install -t ${DESTDIR}/usr/bin ${GOPATH}/bin/gclone

clean:
	go clean ./...
	find . -name \*~ | xargs -r rm -f
	rm -rf build docs/public
	rm -f gclone fs/operations/operations.test fs/sync/sync.test fs/test_all.log test.log

website:


tarball:
	git archive -9 --format=tar.gz --prefix=gclone-$(TAG)/ -o build/gclone-$(TAG).tar.gz $(TAG)

vendorball:
	go mod vendor
	tar -zcf build/gclone-$(TAG)-vendor.tar.gz vendor
	rm -rf vendor

sign_upload:
	cd build && md5sum gclone-v* | gpg --clearsign > MD5SUMS
	cd build && sha1sum gclone-v* | gpg --clearsign > SHA1SUMS
	cd build && sha256sum gclone-v* | gpg --clearsign > SHA256SUMS

check_sign:
	cd build && gpg --verify MD5SUMS && gpg --decrypt MD5SUMS | md5sum -c
	cd build && gpg --verify SHA1SUMS && gpg --decrypt SHA1SUMS | sha1sum -c
	cd build && gpg --verify SHA256SUMS && gpg --decrypt SHA256SUMS | sha256sum -c

upload_github: cross
	./bin/upload-github $(TAG)

cross:
	go run bin/cross-compile.go -release "" $(BUILD_FLAGS) $(BUILDTAGS) $(BUILD_ARGS) $(TAG)

beta:

log_since_last_release:
	git log $(LAST_TAG)..

compile_all:
	go run bin/cross-compile.go -compile-only $(BUILD_FLAGS) $(BUILDTAGS) $(BUILD_ARGS) $(TAG)

ci_upload:

ci_beta:

# Fetch the binary builds from GitHub actions
fetch_binaries:

serve:

tag:	retag doc

retag:
	@echo "Version is $(VERSION)"
	git tag -f -s -m "Version $(VERSION)" $(VERSION)

startdev:

startstable:

winzip:
	zip -9 gclone-$(TAG).zip gclone.exe
