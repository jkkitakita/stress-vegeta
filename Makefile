# Copyright 2016 Philip G. Porada
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.ONESHELL:
.SHELL := /bin/bash
.PHONY: gen-target attack upload clean
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
YELLOW=$(shell tput setaf 3)
RESET=$(shell tput sgr0)

# default variables.
NOW=`date "+%Y/%m/%d %H:%M:%S"`
SERVICE=sample
DEFAULT_URL=http://example.com
UPLOAD_S3_PATH=sample-docs/stress/$(ENV)/$(SERVICE)
# vegeta variables.
RATE=10 # req / second
DUR=10 # second
DUR_SEC=${DUR}s
TGT=default
TGTS := default action
TGT_FILE=target.txt # If you want to specify TGT_FILE, specify it as an argument of make ex. ENV=dev make gen-target TGT=action TGT_FILE=target-action.txt

# reporting variables.
_revision=$(shell git rev-parse --short HEAD)
_report_title_format="$(ENV)-$(SERVICE)-$(TGT)-$(RATE)-$(DUR_SEC) at $(NOW)(darunia-infra@$(_revision))"
_report_file_format=$(TGT)-$(RATE)r-$(DUR_SEC)

ifeq ($(TGT),default)
	export TGT_URL=$(DEFAULT_URL)
  export TGT_BODY_JSON=$(TGT)
else
	export TGT_URL=$(DEFAULT_URL)/$(TGT)
	export TGT_BODY_JSON=$(TGT)
endif

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | \
		awk 'BEGIN {FS = " ex. "}; {printf "%s \033[36mex. %-30s\033[0m\n", $$1, $$2}'

# 変数確認
# print-vars:
# 	@$(foreach v,$(.VARIABLES),$(info $v=$($v)))

set-env:
	@if [ -z $(ENV) ]; then \
		echo "$(BOLD)$(RED)ENV was not set. ex. ENV=dev make attack$(RESET)"; \
		exit 1; \
	 fi
	@if ! `echo $(TGTS) | grep -q $(TGT)` ; then \
	   echo "$(BOLD)$(RED)TGT is incorrect '$(TGT)'. There are TGTs that you can choose in ($(TGTS))$(RESET)"; \
		 exit 1; \
	 fi

gen-target: set-env ## Generate target file. ex. ENV=dev make gen-target TGT=action
	@envsubst < target.txt.template > $(TGT_FILE) && cat $(TGT_FILE) && \
		echo "\n\n$(BOLD)$(GREEN)Success. generate $(TGT_FILE)$(RESET)\n"

attack: gen-target ## Vegeta Attack! ex. ENV=dev make attack RATE=20 DUR=5 TGT=action
	@if [ ! -e $(TGT_FILE) ]; then \
		echo "$(BOLD)$(RED)'$(TGT_FILE)' not found. Please generate $(TGT_FILE) ex. ENV=dev make gen-target TGT=action$(RESET)"; \
		exit 1; \
	 fi
	@vegeta attack -rate=$(RATE) -duration=$(DUR_SEC) -targets=$(TGT_FILE) | \
		tee reports/bin/$(_report_file_format).bin | \
		vegeta report
	@cat reports/bin/$(_report_file_format).bin | \
		vegeta report -type=json > reports/json/$(_report_file_format).json
	@cat reports/bin/$(_report_file_format).bin | \
		vegeta plot --title $(_report_title_format) > reports/html/$(_report_file_format).html \
		&& echo "\n$(BOLD)$(GREEN)Success. attack and generate report files $(_report_file_format)[.html,.bin,.json] in reports dir.$(RESET)"

upload: set-env ## Upload report files to s3. ex. ENV=dev make upload
	@aws s3 cp reports s3://$(UPLOAD_S3_PATH) --recursive --exclude "*.keep" && \
		echo "\n$(BOLD)$(GREEN)Upload done.Please check the URL.\nhttps://s3-us-west-2.amazonaws.com/$(UPLOAD_S3_PATH)/$(RESET)"

clean: ## Delete report files in reports dir. ex. make clean
	@find reports -name "*.bin" -o -name "*.html" -o -name "*.json"|xargs rm 
