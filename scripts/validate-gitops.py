#!/usr/bin/env python3
"""Validate homelab GitOps generator inputs.

This checks the custom app descriptor files consumed by ApplicationSet. Kubernetes
schema tools cannot validate these because they are parameter files, not manifests.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import jsonschema
import yaml


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "schemas" / "argocd-app-descriptor.schema.json"
PROJECTS_PATH = ROOT / "categories" / "projects.yaml"
INFRA_CATEGORY_PATH = ROOT / "categories" / "infrastructure.yaml"
APPS_CATEGORY_PATH = ROOT / "categories" / "applications.yaml"
ROOT_APP_PATH = ROOT / "bootstrap" / "root-app.yaml"
APP_DESCRIPTOR_ROOT = ROOT / "argocd-apps"
HOMELAB_REPO = "https://github.com/isaacwallace123/homelab-k8s.git"


def load_yaml_documents(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        docs = [doc for doc in yaml.safe_load_all(handle) if doc is not None]
    if not all(isinstance(doc, dict) for doc in docs):
        raise ValueError(f"{path}: YAML documents must be mappings")
    return docs


def load_single_yaml(path: Path) -> dict[str, Any]:
    docs = load_yaml_documents(path)
    if len(docs) != 1:
        raise ValueError(f"{path}: expected exactly one YAML document, found {len(docs)}")
    return docs[0]


def load_projects() -> dict[str, dict[str, Any]]:
    projects: dict[str, dict[str, Any]] = {}
    for doc in load_yaml_documents(PROJECTS_PATH):
        if doc.get("kind") != "AppProject":
            raise ValueError(f"{PROJECTS_PATH}: expected only AppProject resources")
        name = doc.get("metadata", {}).get("name")
        if not isinstance(name, str):
            raise ValueError(f"{PROJECTS_PATH}: AppProject is missing metadata.name")
        projects[name] = doc
    return projects


def source_allowed(repo_url: str, project: dict[str, Any]) -> bool:
    sources = project.get("spec", {}).get("sourceRepos", [])
    return "*" in sources or repo_url in sources


def namespace_allowed(namespace: str, project: dict[str, Any]) -> bool:
    destinations = project.get("spec", {}).get("destinations", [])
    for destination in destinations:
        if destination.get("server") != "https://kubernetes.default.svc":
            continue
        allowed = destination.get("namespace")
        if allowed == "*" or allowed == namespace:
            return True
    return False


def expected_project_for_path(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    if relative.startswith("argocd-apps/apps/portfolio/"):
        return "portfolio"
    if relative.startswith("argocd-apps/apps/"):
        return "applications"
    if relative.startswith("argocd-apps/infrastructure/monitoring/"):
        return "monitoring"
    if relative.startswith("argocd-apps/infrastructure/"):
        return "infrastructure"
    raise ValueError(f"{path}: descriptor must live under argocd-apps/apps or argocd-apps/infrastructure")


def validate_descriptor(path: Path, schema: dict[str, Any], projects: dict[str, dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    try:
        descriptor = load_single_yaml(path)
        jsonschema.validate(descriptor, schema)
    except Exception as exc:  # noqa: BLE001 - report all validation errors consistently
        return [f"{path.relative_to(ROOT)}: {exc}"]

    project_name = descriptor["project"]
    project = projects.get(project_name)
    if project is None:
        errors.append(f"{path.relative_to(ROOT)}: unknown project {project_name!r}")
    else:
        if not source_allowed(descriptor["repoURL"], project):
            errors.append(
                f"{path.relative_to(ROOT)}: repoURL {descriptor['repoURL']!r} is not allowed by project {project_name!r}"
            )
        if not namespace_allowed(descriptor["namespace"], project):
            errors.append(
                f"{path.relative_to(ROOT)}: namespace {descriptor['namespace']!r} is not allowed by project {project_name!r}"
            )

    expected_project = expected_project_for_path(path)
    if project_name != expected_project:
        errors.append(
            f"{path.relative_to(ROOT)}: project {project_name!r} does not match directory expectation {expected_project!r}"
        )

    filename = path.name
    has_app_path = "appPath" in descriptor
    if filename.endswith("-git-app.yaml") and not has_app_path:
        errors.append(f"{path.relative_to(ROOT)}: *-git-app.yaml descriptors must use appPath")
    if filename.endswith("-helm-app.yaml") and has_app_path:
        errors.append(f"{path.relative_to(ROOT)}: *-helm-app.yaml descriptors must use chart/values")
    if filename.endswith("-helm-app.yaml") and "*" in descriptor["targetRevision"]:
        errors.append(f"{path.relative_to(ROOT)}: Helm chart targetRevision must be pinned, not a wildcard")
    if not filename.endswith(("-git-app.yaml", "-helm-app.yaml")):
        errors.append(f"{path.relative_to(ROOT)}: descriptor filename must end with -git-app.yaml or -helm-app.yaml")

    if has_app_path:
        app_path_value = descriptor["appPath"]
        if descriptor["repoURL"] == HOMELAB_REPO:
            # Homelab-sourced git apps point at manifests vendored in this repo; validate them locally.
            app_path = ROOT / app_path_value
            if not app_path.exists() or not app_path.is_dir():
                errors.append(f"{path.relative_to(ROOT)}: appPath {app_path_value!r} does not exist")
            if not app_path_value.startswith(("manifests/apps/", "manifests/infra/")):
                errors.append(f"{path.relative_to(ROOT)}: homelab-sourced appPath must live under manifests/apps/ or manifests/infra/")
            if project_name == "applications" and not app_path_value.startswith("manifests/apps/"):
                errors.append(f"{path.relative_to(ROOT)}: applications project descriptors must point under manifests/apps/")
            if project_name in {"infrastructure", "monitoring"} and not app_path_value.startswith("manifests/infra/"):
                errors.append(f"{path.relative_to(ROOT)}: infrastructure/monitoring descriptors must point under manifests/infra/")
        # Externally-sourced descriptors (e.g. portfolio-v3) reference paths in the remote repo,
        # which cannot be validated locally; the project source/namespace allow-lists gate them instead.

    return errors


def validate_categories() -> list[str]:
    errors: list[str] = []
    for path in (INFRA_CATEGORY_PATH, APPS_CATEGORY_PATH):
        for doc in load_yaml_documents(path):
            template_project = doc.get("spec", {}).get("template", {}).get("spec", {}).get("project")
            if template_project != "{{project}}":
                errors.append(f"{path.relative_to(ROOT)}: ApplicationSet template project must be '{{{{project}}}}'")

    projects = load_projects()
    for required in ("infrastructure", "applications", "monitoring", "lab-observability", "portfolio"):
        if required not in projects:
            errors.append(f"{PROJECTS_PATH.relative_to(ROOT)}: missing AppProject {required!r}")

    root_app = load_single_yaml(ROOT_APP_PATH)
    if root_app.get("kind") != "Application":
        errors.append(f"{ROOT_APP_PATH.relative_to(ROOT)}: root app must be an ArgoCD Application")
    if root_app.get("metadata", {}).get("name") != "root":
        errors.append(f"{ROOT_APP_PATH.relative_to(ROOT)}: root app metadata.name must be root")
    if root_app.get("spec", {}).get("source", {}).get("path") != "categories":
        errors.append(f"{ROOT_APP_PATH.relative_to(ROOT)}: root app must point at categories/")
    if root_app.get("spec", {}).get("source", {}).get("repoURL") != HOMELAB_REPO:
        errors.append(f"{ROOT_APP_PATH.relative_to(ROOT)}: root app repoURL must be {HOMELAB_REPO}")

    return errors


def main() -> int:
    with SCHEMA_PATH.open("r", encoding="utf-8") as handle:
        schema = json.load(handle)

    projects = load_projects()
    errors: list[str] = []
    descriptors = sorted(APP_DESCRIPTOR_ROOT.rglob("*-app.yaml"))
    if not descriptors:
        errors.append("argocd-apps: no app descriptors found")

    for descriptor_path in descriptors:
        errors.extend(validate_descriptor(descriptor_path, schema, projects))

    errors.extend(validate_categories())

    if errors:
        print("GitOps validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"GitOps validation passed: {len(descriptors)} app descriptors, {len(projects)} projects")
    return 0


if __name__ == "__main__":
    sys.exit(main())
