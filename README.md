# How to Automate Database Password Rotation in Terraform

[medium](https://medium.com/@antoxa.zimm/how-to-automate-database-password-rotation-in-terraform-f2282b3b80c5)

![intro](/docs/preview.jpeg)

Automatic database password rotation (e.g., every X days) is an important security practice that reduces the risk of credential compromise. This article will explore implementing password rotation using Terraform with Azure Database for PostgreSQL Flexible Server.

## 1. Approach to Password Rotation in Terraform

Terraform uses providers to interact with cloud platforms, APIs, and services. In this example, we use three providers:

- `azurerm` (Azure Resource Manager Provider): Manages resources in Microsoft Azure, including PostgreSQL Flexible Server. [Reference](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- `random` (Random Provider): Generates random values, such as passwords. [Reference](https://registry.terraform.io/providers/hashicorp/random/latest)
- `time` (Time Provider): Provides time-based resources like rotation triggers. [Reference](https://registry.terraform.io/providers/hashicorp/time/latest)

Terraform does not natively support periodic operations, but we can use the `time` provider to automate resource updates at specific intervals. In this example, we:

- Use `time_rotating` to control the password rotation frequency.
- Generate a new login and password `using random_password`.
- Pass the updated credentials to `azurerm_postgresql_flexible_server`.

## 2. Terraform Configuration for Password Rotation in Azure PostgreSQL

### a. Providers configuration

```hcl
provider "azurerm" {
  features {}
}

provider "random" {}

provider "time" {}
```

\*\* the `azurerm` provider is used to create a resource that utilizes a login and password. It can be replaced with other providers like `aws`, `google`, or `kubernetes`, depending on the infrastructure.

### b. Random Login and Password Generation Every Day

Terraform uses the `time_rotating` resource to trigger automatic password regeneration daily. This ensures that credentials remain fresh and reduces security risks. The `random_password` resource generates new login and password values each time the `time_rotating` resource updates.

- The `rotation_days = 1` setting ensures that passwords are regenerated every 24 hours.
- The `random_password.postgresql_flexible_server_login` resource generates a 32-character login without special characters.
- The `random_password.postgresql_flexible_server_password` resource generates a 32-character password, including special characters for enhanced security.
- The `keepers` argument ties the generated values to the `time_rotating` resource, ensuring they are refreshed whenever the rotation trigger updates.

```hcl
resource "time_rotating" "postgresql_flexible_server_login_password_rotating" {
  rotation_days = 1
}

resource "random_password" "postgresql_flexible_server_login" {
  length  = 32
  special = false
  keepers = {
    rotation_time = time_rotating.postgresql_flexible_server_login_password_rotating.id
  }
}

resource "random_password" "postgresql_flexible_server_password" {
  length           = 32
  special          = true
  override_special = "!#*()-_+[]{}<>"
  keepers = {
    rotation_time = time_rotating.postgresql_flexible_server_login_password_rotating.id
  }
}
```

> __Note__:
> The current Terraform configuration generates a 32-character password with special characters (longer is better). This is a recommended and safe approach.
>
> __Note__:
> Do not use the generated database admin password in connection strings. If an application or connection string needs a password, a new login with limited privileges should be created instead of using the admin password.

### c. Usage of Generated values

Once the login and password are generated using `random_password`, they need to be assigned to the database administrator account. This ensures that every time the credentials are rotated, the database uses the newly generated values.

- The `azurerm_resource_group` resource creates a resource group in Azure to hold the database server.
- The `azurerm_postgresql_flexible_server` resource provisions a PostgreSQL Flexible Server instance.
- The `administrator_login` value must start with a letter, so we prepend an `l` to the randomly generated login value to meet PostgreSQL requirements.
- The `administrator_password` is assigned from `random_password.postgresql_flexible_server_password.result`.
- The `lifecycle` block is configured to ignore certain changes, preventing unnecessary redeployment of the database instance due to zone or high availability settings.

With this setup, the database will always have an up-to-date administrator login and password, ensuring security and compliance with rotation policies.

```hcl
resource "azurerm_resource_group" "default" {
  name     = "password-rotation-in-terraform-rg"
  location = "West Europe"
}

resource "azurerm_postgresql_flexible_server" "default" {
  name                   = "password-rotation-in-terraform-pgsql"
  resource_group_name    = azurerm_resource_group.default.name
  location               = azurerm_resource_group.default.location
  version                = "16"
  administrator_login    = "l${random_password.postgresql_flexible_server_login.result}"
  administrator_password = random_password.postgresql_flexible_server_password.result
  sku_name               = "B_Standard_B1ms"
  lifecycle {
    ignore_changes = [
      zone, high_availability.0.standby_availability_zone
    ]
  }
}
```

## 3. First Infrastructure Provisioning

Before running Terraform, ensure that you have the necessary permissions and environment variables configured for your cloud provider. The following commands will initialize Terraform, generate an execution plan, and apply the changes to provision the infrastructure.

### a. Initialize Terraform

This downloads the required provider plugins and sets up the backend for state management

```bash
terraform init
```

expected output:

```bash
> Initializing the backend...
> Initializing provider plugins...
> - Finding latest version of hashicorp/azurerm...
> - Finding latest version of hashicorp/time...
> - Finding latest version of hashicorp/random...
> ...
> Terraform has been successfully initialized!
```

### b. Generate the Execution Plan

This previews the changes that Terraform will apply

```bash
terraform plan -out=plan.tfplan
```

expected output:

```bash
> Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following
> symbols:
>   + create
>
> Terraform will perform the following actions:
>
>   # azurerm_postgresql_flexible_server.default will be created
>   + resource "azurerm_postgresql_flexible_server" "default" {
> ...
> Plan: 5 to add, 0 to change, 0 to destroy.
> Saved the plan to: plan.tfplan
```

### c. Apply the Changes

This step applies the Terraform execution plan and provisions the necessary infrastructure.

```bash
terraform apply "plan.tfplan"
```

expected output:

```bash
> time_rotating.postgresql_flexible_server_login_password_rotating: Creating...
> time_rotating.postgresql_flexible_server_login_password_rotating: Creation complete after 0s [id=2025-03-09T10:35:03Z]
> random_password.postgresql_flexible_server_login: Creating...
> random_password.postgresql_flexible_server_password: Creating...
> random_password.postgresql_flexible_server_login: Creation complete after 0s [id=none]
> random_password.postgresql_flexible_server_password: Creation complete after 0s [id=none]
> ...
> Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

## 4. Subsequent Runs with Automatic Password Rotation

After the password rotation period expires, Terraform will automatically replace the password. This process ensures that credentials remain fresh and secure.

### a. Plan the changes

Terraform recognizes changes in the `time_rotating` resource and marks dependent resources (such as `random_password` and `azurerm_postgresql_flexible_server`) for recreation or update.

```bash
terraform plan -out=plan.tfplan
```

expected output:

```bash
> time_rotating.postgresql_flexible_server_login_password_rotating: Refreshing state... [id=2025-03-09T10:57:27Z]
> random_password.postgresql_flexible_server_login: Refreshing state... [id=none]
> random_password.postgresql_flexible_server_password: Refreshing state... [id=none]
> ...
> Note: Objects have changed outside of Terraform
> ...
> Terraform detected the following changes made outside of Terraform since the last "terraform apply" which may have affected this plan:
>
>   # time_rotating.postgresql_flexible_server_login_password_rotating has been deleted
>   - resource "time_rotating" "postgresql_flexible_server_login_password_rotating" {
>       - id               = "2025-03-09T11:14:52Z" -> null
>         # (10 unchanged attributes hidden)
>     }
> ...
> Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
>   + create
> -/+ destroy and then create replacement
>
> Terraform will perform the following actions:
>
>   # azurerm_postgresql_flexible_server.default will be created
>   + resource "azurerm_postgresql_flexible_server" "default" {
>       + administrator_login           = (known after apply)
>       + administrator_password        = (sensitive value)
>       ...
>     }
>
>   # random_password.postgresql_flexible_server_login must be replaced
> -/+ resource "random_password" "postgresql_flexible_server_login" {
>       ~ bcrypt_hash = (sensitive value)
>       ~ id          = "none" -> (known after apply)
>       ~ keepers     = { # forces replacement
>           ~ "rotation_time" = "2025-03-09T11:14:52Z" -> (known after apply)
>         }
>       ~ result      = (sensitive value)
>         # (10 unchanged attributes hidden)
>     }
>
>   # random_password.postgresql_flexible_server_password must be replaced
> -/+ resource "random_password" "postgresql_flexible_server_password" {
>       ~ bcrypt_hash      = (sensitive value)
>       ~ id               = "none" -> (known after apply)
>       ~ keepers          = { # forces replacement
>           ~ "rotation_time" = "2025-03-09T11:14:52Z" -> (known after apply)
>         }
>       ~ result           = (sensitive value)
>         # (11 unchanged attributes hidden)
>     }
>
>   # time_rotating.postgresql_flexible_server_login_password_rotating will be created
>   + resource "time_rotating" "postgresql_flexible_server_login_password_rotating" {
>       + day              = (known after apply)
>       + hour             = (known after apply)
>       + id               = (known after apply)
>       + minute           = (known after apply)
>       + month            = (known after apply)
>       + rfc3339          = (known after apply)
>       + rotation_minutes = 1
>       + rotation_rfc3339 = (known after apply)
>       + second           = (known after apply)
>       + unix             = (known after apply)
>       + year             = (known after apply)
>     }
>
> Plan: 4 to add, 0 to change, 2 to destroy.
```

### b. Apply the changes

Terraform destroys the outdated credentials and provisions new ones.

```bash
terraform apply "plan.tfplan"
```

expected output:

```bash
> random_password.postgresql_flexible_server_login: Destroying... [id=none]
> random_password.postgresql_flexible_server_password: Destroying... [id=none]
> random_password.postgresql_flexible_server_login: Destruction complete after 0s
> random_password.postgresql_flexible_server_password: Destruction complete after 0s
> time_rotating.postgresql_flexible_server_login_password_rotating: Creating...
> ...
> Apply complete! Resources: 4 added, 0 changed, 2 destroyed.
```

This process ensures that the database credentials are automatically rotated without manual intervention.

## 5. Further Automation

This process can be automated using CI/CD pipelines such as GitHub Actions, which can periodically trigger Terraform execution. While automation can be implemented using CI/CD pipelines such as GitHub Actions, this article focuses solely on manual execution. Additionally, aspects like backend configuration, secret management, and infrastructure state handling can further enhance the solution but are not covered here.

## 6. Destroy resources

After testing, ensure all resources are deleted to free up cloud capacity and avoid unnecessary costs.

### a. Plan the destroy

```bash
terraform plan -out=destroy.tfplan -destroy
```

expected output:

```bash
> time_rotating.postgresql_flexible_server_login_password_rotating: Refreshing state... [id=2025-03-09T11:26:57Z]
> random_password.postgresql_flexible_server_login: Refreshing state... [id=none]
> random_password.postgresql_flexible_server_password: Refreshing state... [id=none]
> ...
> Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
>   - destroy
> ...
> Plan: 0 to add, 0 to change, 4 to destroy.
```

### b. Destroy resources

```bash
terraform apply "destroy.tfplan"
```

expected output:

```bash
> azurerm_postgresql_flexible_server.default: Destroying... [id=/subscriptions/.../resourceGroups/password-rotation-in-terraform-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/password-rotation-in-terraform-pgsql]
> azurerm_postgresql_flexible_server.default: Still destroying... [id=/subscriptions/.../password-rotation-in-terraform-pgsql, 10s elapsed]
> azurerm_postgresql_flexible_server.default: Destruction complete after 13s
> azurerm_resource_group.default: Destroying... [id=/subscriptions/.../resourceGroups/password-rotation-in-terraform-rg]
> ...
> Apply complete! Resources: 0 added, 0 changed, 4 destroyed.
```

This command ensures that all resources created by Terraform are properly deleted, freeing up cloud resources and preventing unnecessary costs.
