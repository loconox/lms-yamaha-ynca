PLUGIN_NAME := YamahaYNCA
PLUGIN_DIR  := Plugins/$(PLUGIN_NAME)
DIST_DIR    := dist
ZIP         := $(DIST_DIR)/$(PLUGIN_NAME).zip

# Auto-detected when run locally from a git clone with an 'origin' remote on
# GitHub; overridden explicitly by CI (make repo-xml REPO=owner/name ...).
REPO    ?= $(shell git config --get remote.origin.url 2>/dev/null | sed -E -e 's#^git@github\.com:##' -e 's#^https://github\.com/##' -e 's#\.git$$##')
VERSION ?= $(shell sed -n 's#.*<version>\(.*\)</version>.*#\1#p' $(PLUGIN_DIR)/install.xml)
SHA1    ?= $(shell sha1sum $(ZIP) 2>/dev/null | cut -d' ' -f1)
URL     := https://github.com/$(REPO)/releases/latest/download/$(PLUGIN_NAME).zip

SOURCES := $(shell find $(PLUGIN_DIR) -type f)

.PHONY: all build zip sha1 version repo-xml clean

all: build

build: $(ZIP)

zip: $(ZIP)

$(ZIP): $(SOURCES)
	mkdir -p $(DIST_DIR)
	rm -f $(ZIP)
	cd Plugins && zip -r -X ../$(ZIP) $(PLUGIN_NAME) -x '*.DS_Store'

sha1: $(ZIP)
	@sha1sum $(ZIP)

version:
	@echo $(VERSION)

# Regenerates repo.xml from repo.xml.tmpl, pointing at the "latest release"
# download URL for $(REPO) and stamping the current zip's sha1 + the version
# declared in install.xml. Run after pushing the repo to GitHub, or let the
# release workflow do it on every tag.
repo-xml: $(ZIP)
	@test -n "$(REPO)" || { echo "REPO not set (no 'origin' remote found) - pass REPO=owner/name"; exit 1; }
	sed \
		-e 's#__URL__#$(URL)#' \
		-e 's#__SHA1__#$(SHA1)#' \
		-e 's#__VERSION__#$(VERSION)#' \
		repo.xml.tmpl > repo.xml
	@echo "Generated repo.xml (repo=$(REPO) version=$(VERSION) sha1=$(SHA1))"

clean:
	rm -rf $(DIST_DIR)
