.PHONY: help upgrade requirements clean quality requirements docs \
	test test-all coverage pii_check \
	compile_translations dummy_translations extract_translations \
	fake_translations pull_translations push_translations test test-python \
	test-js quality-python quality-js

.DEFAULT_GOAL := help

define BROWSER_PYSCRIPT
import os, webbrowser, sys
try:
	from urllib import pathname2url
except:
	from urllib.request import pathname2url

webbrowser.open("file://" + pathname2url(os.path.abspath(sys.argv[1])))
endef
export BROWSER_PYSCRIPT
BROWSER := python -c "$$BROWSER_PYSCRIPT"

help: ## display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

clean: ## remove generated byte code, coverage reports, and build artifacts
	find . -name '*.pyc' -o -name '*.pyo' -o -name '*~' -delete
	rm -fr build/ dist/ *.egg-info
	rm -rf pii_report

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	pip install -q pip-tools
	pip-compile --rebuild --upgrade -o requirements/base.txt requirements/base.in
	pip-compile --rebuild --upgrade -o requirements/dev.txt requirements/dev.in
	pip-compile --rebuild --upgrade -o requirements/doc.txt requirements/doc.in
	pip-compile --rebuild --upgrade -o requirements/quality.txt requirements/quality.in
	pip-compile --rebuild --upgrade -o requirements/test.txt requirements/test.in
	# Let tox control the Django and djangorestframework versions for tests
	sed -i.tmp '/^[d|D]jango==/d' requirements/test.txt
	sed -i.tmp '/^djangorestframework==/d' requirements/test.txt
	rm requirements/test.txt.tmp

requirements: ## install development environment requirements
	pip install -qr requirements/dev.txt --exists-action w
	pip-sync requirements/*.txt requirements/private.*

install: requirements
	./manage.py migrate --settings=test_settings
	npm install

coverage: clean ## generate and view HTML coverage report
	py.test --cov=edx_proctoring --cov-report html --ds=test_settings
	$(BROWSER) htmlcov/index.html

pii_check: ## check for PII annotations on all Django models
	DJANGO_SETTINGS_MODULE=test_settings \
	code_annotations django_find_annotations --config_file .pii_annotations.yml --lint --report --coverage

docs: ## generate Sphinx HTML documentation, including API docs
	tox -e docs
	$(BROWSER) docs/_build/html/index.html

quality-js: lint-js

quality-python: ## Run python linters
	tox -e quality

quality: quality-js quality-python ## Run linters

test-python: clean ## run tests in the current virtualenv
	pip install -e .
	py.test --cov=edx_proctoring --cov-report=html --ds=test_settings -n 3

test-js:
	gulp test

lint-js:
	./node_modules/.bin/eslint --ignore-pattern 'edx_proctoring/static/index.js' --ext .js --ext .jsx .
	./node_modules/.bin/eslint --config .eslintrc.worker.json 'edx_proctoring/static/index.js'

test-all: ## run tests on every supported Python/Django combination
	tox -e quality
	tox

diff_cover: test
	diff-cover coverage.xml

## Localization targets

extract_translations: ## extract strings to be translated, outputting .mo files
	cd edx_proctoring && ../manage.py makemessages -l en -v1 -d django
	cd edx_proctoring && ../manage.py makemessages -l en -v1 -d djangojs

compile_translations: ## compile translation files, outputting .po files for each supported language
	cd edx_proctoring && ../manage.py compilemessages

detect_changed_source_translations:
	cd edx_proctoring && i18n_tool changed

pull_translations: ## pull translations from Transifex
	tx pull -af --mode reviewed --minimum-perc=1

push_translations: ## push source translation files (.po) from Transifex
	tx push -s

validate_translations: ## Test translation files
	cd edx_proctoring && i18n_tool validate -v

dummy_translations: ## generate dummy translation (.po) files
	cd edx_proctoring && i18n_tool dummy

install-js: ## install JavaScript dependencies
	npm install

build_dummy_translations: extract_translations dummy_translations compile_translations ## generate and compile dummy translation files

check_translations_up_to_date: build_dummy_translations detect_changed_source_translations ## validate translations

test: test-python test-js ## run tests
