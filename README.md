# Terraform Bundle Container

This container is responsible for building a [Terraform Bundle](https://github.com/hashicorp/terraform/tree/master/tools/terraform-bundle), which
is a custom terraform binary which contains the providers we need on a day to day basis.

To update a version for a given provider or add a new one, edit the version in the `form3-bundle-<version>.json` file. The file is in JSON
format, and each provider should have a `name`, `version` and `url` properties.
The value of the `version` field **MUST** correspond to an existing tag.

Add the new version to the `matrix` section of the `.travis.yml` file so that it will get built on PR merge.

Once you have made your changes, raise a PR, get
it approved and once it's merged, it will trigger a Travis build which will generate the bundle, publish the generated ZIP file in Github as a Release
and call TFE's REST api so that the new bundle is installed automatically. You'll have to update the Terraform
version used by the workspaces in TFE.

## Bumping to a new version of Terraform

To bump to a new version of Terraform, adequate `terraform-bundle-<version>_<os>_<arch>` must be placed on the `bin/` directory.
For the time being, these files must be manually built from the `tools/terraform-bundle` directory in https://github.com/hashicorp/terraform, adequately renamed and copied into the `bin/` directory.
This procedure will be automated in the future.

## Building terraform-bundle

run `make TF_TAG=terraform_tag tf-bundle-build`

example `make TF_TAG=v0.12.30 tf-bundle-build`

This target will checkout `terraform` repository for the given tag in
a `tmp` directory and build terraform-builder for you. Once it's done
it will copy it to your `bin/` directory.

### Build requirements

the make target builds with `CGO_enabled=0` and `-trimpath`. Provider
binaries needs to be statically linked hence the first option. The
second option is to be able to generate reproducible binaries. I.e
running build over the same tag should yield the same binary.

## Using the Docker container

This repository publishes our Terraform Bundle in a docker container so that our apps can use it for their automated tests. One docker
container per major Terraform version will be published, so for example if we build bundles for versions `0.11.14` and `0.12.30`, then
the following containers will be published: `0.11-latest` and `0.12-latest` which can then be used in a `docker-compose.yml` like this:

```yaml
  indoor_terraform:
    image: ${PRIMARY_DOCKER_REGISTRY}/tech.form3/form3-terraform-bundle:0.12-latest
    volumes:
      - ./tf:/tf
      - ./tf_test_overrides:/tf_test_overrides
    depends_on:
      - postgresql
      - vault
      - wait_for
    environment:
      TFE_TOKEN: ${TFE_TOKEN}
      TF_VAR_environment: local
      TF_VAR_api_vault_address: http://vault:8200
      TF_VAR_api_vault_token: 'devToken'
      TF_VAR_stack_name: local
      TF_VAR_psql_user: postgres
      TF_VAR_psql_password: password
      TF_VAR_psql_host: postgresql
      TF_VAR_psql_port: 5432
```

This configuration assumes there is some configuration in the `docker-compose` file to wait for container to be ready. The container
provides 2 mount directories:

- `/tf`: The main Terraform configuration should be mounted here
- `/tf_test_overrides`: The overrides for testing. So for example, some `_override.tf` files which can override the AWS provider
to point to LocalStack. The main purpose of this directory is to be copied on top of the `tf` directory, allowing the user to overwrite
files as well. See [Terraform Override](https://www.terraform.io/docs/language/files/override.html) for more details on how to use overrides.

### Terraform Override gotchas

`form3-terraform-bundle` container will ignore all files with `aws.tf` suffix (e.g: `file_name.aws.tf`) before running `terraform init` and `terraform apply` in the container.

If you have a `data` resource in your main TF files and the actual `resource` is defined elsewhere (different repo), then you will need to have a **mock** `resource` defined in the override directory along with the **override** `data` that will be referencing a mock `resource`.

Example:

In your main tf files you have this `data` resource which references an existing AWS resource defined in a different repo:

```terraform
data aws_sns_topic "sns_notification_topic" {
  name = "${var.stack_name}-topic-original"
}
```

In your terraform overrides you will have to create a new `resource`:

```terraform
resource "aws_sns_topic" "sns_notification_topic_local" {
  name = "${var.stack_name}-topic-local" #tfsec:ignore:AWS016 tfsec:ignore:CUS001
}
```

and then refer to it in `data` resource override:

```terraform
data aws_sns_topic "sns_notification_topic" {
  name = aws_sns_topic.sns_notification_topic_local.name
}
```

An example is provided in the `docker/example` directory.
