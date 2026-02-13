# Developing

This document is aimed at the developers of VocalDocs. If you want to deploy the solution without changing it, please refer to the instructions in the main [README.md](./README.md).

## Create your local Python environment

VocalDocs is using Python in its backend. To be able to efficiently develop, create a virtual environment and install the dependencies used throughout the project for local IDE support.

```bash
python3 -m venv .env
source .env/bin/activate
pip install --upgrade pip
pip install -r ./requirements.txt
```

Set your IDEs Python interpreter to this new environment.

## Security

The project environment comes with [bandit](https://github.com/PyCQA/bandit) and [semgrep](https://github.com/semgrep/semgrep) as installed dependencies. Ensure you have [tfsec](https://github.com/aquasecurity/tfsec) installed in addition.

Execute these commands from the project root directory to check for security findings:

```bash
bandit -r ./src
```

```bash
semgrep scan ./src
```

```bash
tfsec ./src/terraform_project
```
