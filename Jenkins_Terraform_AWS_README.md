# Jenkins + GitHub Webhook + Terraform on AWS

## 1. Project Overview

This project automates Terraform infrastructure management on AWS using
Jenkins and GitHub.

**One-line flow:** A developer pushes a change to GitHub → the GitHub
webhook notifies Jenkins → Jenkins checks out the configured branch →
Terraform initializes its remote state in S3 → validates and plans the
infrastructure changes → waits for approval when destroying resources →
runs the approved Terraform action.

### Tools used

  -----------------------------------------------------------------------
  Tool / Service                      Purpose
  ----------------------------------- -----------------------------------
  GitHub                              Stores Terraform files and the
                                      `Jenkinsfile`.

  GitHub Personal Access Token (PAT)  Allows Jenkins to authenticate to a
                                      private repository when using HTTPS
                                      credentials.

  GitHub webhook                      Sends a push event to Jenkins to
                                      start a build.

  Jenkins                             Runs the pipeline stages
                                      automatically.

  AWS IAM role                        Grants the Jenkins EC2 instance
                                      permission to access AWS resources.

  Jenkins Credentials                 Securely stores AWS access key and
                                      secret key if the pipeline uses
                                      static credentials.

  Amazon S3                           Stores Terraform state remotely so
                                      builds can access the same state.

  Terraform                           Creates, updates, plans, or
                                      destroys infrastructure described
                                      by the configuration.

  AWS CLI                             Verifies AWS identity and can be
                                      used for AWS commands in the
                                      pipeline.
  -----------------------------------------------------------------------

## 2. Project details used in this lab

Update these values if your environment changes.

  ----------------------------------------------------------------------------------------------------
  Setting                             Value
  ----------------------------------- ----------------------------------------------------------------
  GitHub repository                   `https://github.com/swapnibrad/3ri-batch-DevOps_0926b1668.git`

  Branch                              `terraform-deploy`

  Jenkinsfile                         `Jenkinsfile` at the repository root

  Terraform state key                 `dev/terraform.tfstate`
  ----------------------------------------------------------------------------------------------------

> **Important:** The S3 backend region and AWS provider region can
> differ, but each must match the intended bucket/resources. Confirm the
> actual values in `backend.tf`, `project.tf`, and `terraform.tfvars`
> before running the pipeline. The previously configured bucket name
> `anuradha.bucket.12345` was reported as nonexistent. Create a bucket
> that actually exists and update `backend.tf` with its exact name. Do
> not use a made-up bucket name.

## 3. Create an S3 bucket for Terraform state

Terraform state records which real resources Terraform manages. Keeping
it in S3 allows Jenkins builds to use a shared state file rather than
relying on a temporary workspace.

### 3.1 Create the bucket

In the AWS Console:

1.  Sign in to the intended AWS account.
2.  Open **Amazon S3 → Buckets → Create bucket**.
3.  Enter a globally unique bucket name, for example
    `mycompany-terraform-state-<unique-suffix>`. Replace this example
    with your own name.
4.  Select the backend region you intend to use, such as `ap-south-1` if
    that matches your `backend.tf`.
5.  Keep **Block all public access** enabled.
6.  Leave default encryption enabled (SSE-S3 is sufficient for a basic
    lab; use your organization's encryption standard where applicable).
7.  Create the bucket.

**$:** S3 holds the Terraform state file remotely;
the bucket must exist before `terraform init` can use it.

### 3.2 Enable bucket versioning

In the bucket, open **Properties → Bucket Versioning → Edit → Enable**,
then save.

**$:** Versioning helps recover an earlier state
version if the current state is accidentally changed or overwritten.

### 3.3 Optional: create the bucket with AWS CLI

Run from an AWS CLI session that has permission to create S3 buckets.
Use a globally unique name and the correct region.

For `us-east-1`:

``` bash
aws s3api create-bucket \
  --bucket YOUR-UNIQUE-TERRAFORM-STATE-BUCKET \
  --region us-east-1
```

For a region such as `ap-south-1`:

``` bash
aws s3api create-bucket \
  --bucket YOUR-UNIQUE-TERRAFORM-STATE-BUCKET \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
```

Enable versioning:

``` bash
aws s3api put-bucket-versioning \
  --bucket YOUR-UNIQUE-TERRAFORM-STATE-BUCKET \
  --region YOUR_BUCKET_REGION \
  --versioning-configuration Status=Enabled
```

Verify the bucket:

``` bash
aws s3api head-bucket \
  --bucket YOUR-UNIQUE-TERRAFORM-STATE-BUCKET \
  --region YOUR_BUCKET_REGION
```

### 3.4 Configure `backend.tf`

Example only---replace the bucket name and region with the actual bucket
you created.

``` hcl
terraform {
  backend "s3" {
    bucket       = "YOUR-UNIQUE-TERRAFORM-STATE-BUCKET"
    key          = "dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

**$:** `bucket` names the state bucket, `key` is the
state object's path, `region` is the bucket's region, `encrypt` enables

## 4. Create an IAM role for the Jenkins EC2 instance

An EC2 IAM role lets Jenkins call AWS APIs without storing long-lived
AWS keys on the instance.

### 4.1 Create the role

1.  Open **AWS Console → IAM → Roles → Create role**.
2.  Select **AWS service** as the trusted entity and **EC2** as the use
    case.
3.  Attach an appropriate permissions policy.
4.  Name the role, for example `ec2-access-role`.
5.  Create the role.

**$:** The role gives the EC2 instance temporary AWS

### 4.2 Permissions required

Create a least-privilege policy for the lab. It generally needs:

-   S3 permissions to access the specific Terraform state object and
    lock file in the chosen bucket.
-   Permissions for the AWS resources defined in your Terraform
    configuration (for example, EC2, VPC, security groups, and related
    `Describe` actions).
-   Any additional permissions needed by resources in `project.tf`.

Do not grant `AdministratorAccess` by default. The exact permissions
depend on the resources being created or destroyed.

### 4.3 Attach the role to the Jenkins EC2 instance

1.  Open **EC2 → Instances** and select the Jenkins master/controller
    instance.
2.  Choose **Actions → Security → Modify IAM role**.
3.  Select `ec2-access-role`.
4.  Save the change.

Verify from the Jenkins host:

``` bash
aws sts get-caller-identity
```

The lab previously returned an assumed-role ARN similar to:

``` text
arn:aws:sts::595981035018:assumed-role/ec2-access-role/i-...
```

**$:** This command confirms which AWS identity the
Jenkins host is actually using.

> **Credential approach:** Prefer the EC2 instance role when possible.
> If the pipeline explicitly binds access-key and secret-key
> credentials, those keys may take precedence for AWS CLI/Terraform
> calls. Choose one deliberate credential method, and ensure it has the
> required permissions.

## 5. Create a GitHub Personal Access Token

A PAT lets Jenkins authenticate to a private GitHub repository over
HTTPS. It is separate from the webhook: the webhook itself does not
require a PAT just to send a push event.

### 5.1 Create a fine-grained token

1.  Sign in to GitHub.
2.  Open **Settings → Developer settings → Personal access tokens →
    Fine-grained tokens**.
3.  Select **Generate new token**.
4.  Give it a descriptive name, such as `jenkins-private-repo-read`.
5.  Set an expiration date according to your organization's policy.
6.  Under **Repository access**, choose **Only select repositories** and
    select `3ri-batch-DevOps_0926b1668`.
7.  Under **Repository permissions**, grant **Contents: Read-only** for
    normal Jenkins checkout.
8.  Generate the token and copy it immediately into a password manager
    or directly into Jenkins Credentials.

**$:** The token authenticates Jenkins to read the
private GitHub repository.

### 5.2 Token permissions

-   **Read-only checkout:** `Contents: Read-only` is normally sufficient
    for Jenkins to clone/fetch repository contents.
-   **Jenkins must push commits:** grant write access only if a pipeline
    genuinely needs to push changes; use the minimum required
    permissions.
-   **Webhook:** a push webhook can be configured in the repository
    settings without using the PAT as its webhook secret. A webhook
    secret is a separate optional signing secret.

Never paste the PAT into the `Jenkinsfile`, a public log, or a committed
configuration file. If a token is exposed, revoke it and create a
replacement.

## 6. Add GitHub credentials to Jenkins

If the repository is private and Jenkins checks it out using HTTPS:

1.  Open **Jenkins → Manage Jenkins → Credentials**.
2.  Select the appropriate store/domain (commonly **System → Global
    credentials**).
3.  Click **Add Credentials**.
4.  Choose **Username with password**.
5.  Username: your GitHub username.
6.  Password: the GitHub Token.
7.  ID: use a clear ID such as `github-pat`.
8.  Save.

Then open the Jenkins pipeline job configuration and select this
credential in **Pipeline → SCM → Git → Credentials**.

**$:** Jenkins uses this credential to fetch the
private repository without embedding a password/token in the pipeline.

If your current SCM checkout already works with an existing credential
ID, you can keep using it instead of creating a duplicate.

## 7. Configure the GitHub webhook

A webhook tells Jenkins when a push happens so a build can start
automatically.

### 7.1 Configure the Jenkins job

1.  Open the Jenkins pipeline job.
2.  Click **Configure**.
3.  Under **Build Triggers**, enable **GitHub hook trigger for GITScm
    polling**.
4.  Save the job.

**$:** This enables Jenkins to react to GitHub
webhook events for the configured repository.

### 7.2 Add the webhook in GitHub

1.  Open the repository:
    `https://github.com/swapnibrad/3ri-batch-DevOps_0926b1668`.

2.  Go to **Settings → Webhooks → Add webhook**.

3.  Set **Payload URL** to:

    ``` text
    http://YOUR-JENKINS-HOST:8080/github-webhook/
    ```

    Replace the placeholder with the reachable Jenkins URL. Use HTTPS
    and a valid certificate for a production deployment.

4.  Set **Content type** to `application/json`.

5.  Under event selection, choose **Just the push event**.

6.  Optionally configure a webhook secret and configure matching
    verification at the receiving end according to your Jenkins setup.

7.  Click **Add webhook**.

8.  In GitHub's webhook page, inspect **Recent Deliveries** and confirm
    the delivery succeeded.

**$:** The webhook sends a push event to Jenkins,
which can trigger the pipeline without manual clicking.

## 8. Add AWS access key and secret key to Jenkins Credentials (if using static keys)

The pipeline version used in this lab references two Jenkins
credentials:

-   `aws-access-key-id`
-   `aws-secret-access-key`

To create them:

1.  Open **Jenkins → Manage Jenkins → Credentials**.
2.  Choose the store/domain used by the job.
3.  Click **Add Credentials**.
4.  Choose **Secret text**.
5.  For the first credential:
    -   **Secret:** the AWS access key ID
    -   **ID:** `aws-access-key-id`
6.  Save.
7.  Repeat for the second credential:
    -   **Secret:** the AWS secret access key
    -   **ID:** `aws-secret-access-key`
8.  Save.

**$:** Jenkins injects the credentials into the build
environment so AWS CLI and Terraform can authenticate without putting
keys in source code.


The credential IDs in Jenkins must match the IDs referenced in the
`Jenkinsfile` exactly. Never put the secret values directly in the
Jenkinsfile.

## 9. Configure the Jenkins Pipeline job

1.  From the Jenkins dashboard, click **New Item**.

2.  Enter a job name such as `terraform-aws-pipeline`.

3.  Select **Pipeline** and click **OK**.

4.  Under **General**, enable **This project is parameterized** if your
    Jenkinsfile uses parameters such as `CONFIRM_DESTROY`.

5.  Under **Build Triggers**, enable **GitHub hook trigger for GITScm
    polling**.

6.  In the **Pipeline** section, set **Definition** to **Pipeline script
    from SCM**.

7.  SCM: **Git**.

8.  Repository URL:

    ``` text
    https://github.com/swapnibrad/3ri-batch-DevOps_0926b1668.git
    ```

9.  Credentials: select the GitHub PAT credential you created.

10. Branch specifier:

    ``` text
    */terraform-deploy
    ```

11. Script Path:

    ``` text
    Jenkinsfile
    ```

12. Save.

**$:** Pipeline script from SCM means Jenkins loads
and runs the version-controlled `Jenkinsfile` from the chosen repository
branch.

Do not add a second manual `git clone` stage unless there is a specific
reason; Jenkins already checks out the repository before running a
Pipeline-from-SCM job.

## 10. Recommended repository structure

``` text
3ri-batch-DevOps_0926b1668/
├── Jenkinsfile
├── backend.tf
├── project.tf
├── variables.tf
├── terraform.tfvars
└── README.md
```

  -----------------------------------------------------------------------
  File                                Purpose
  ----------------------------------- -----------------------------------
  `Jenkinsfile`                       Defines Jenkins stages, credentials
                                      usage, planning, approval, and
                                      apply/destroy actions.

  `backend.tf`                        Configures the remote S3 backend
                                      for Terraform state.

  `project.tf`                        Declares AWS resources to manage.

  `variables.tf`                      Defines input variables and their
                                      types.

  `terraform.tfvars`                  Supplies non-secret variable values
                                      for the deployment.

  `README.md`                         Documents setup, workflow,
                                      commands, and troubleshooting.
  -----------------------------------------------------------------------

Do not store AWS secrets, GitHub tokens, or other credentials in
`terraform.tfvars` or any tracked file.

## 11. Understand the pipeline flow

``` text
Developer pushes a commit
          |
          v
GitHub push webhook
          |
          v
Jenkins Pipeline job starts
          |
          v
Checkout repository/branch
          |
          v
Install/check AWS CLI and Terraform
          |
          v
Authenticate to AWS
          |
          v
terraform init
          |
          v
terraform fmt / validate
          |
          v
terraform plan
          |
          v
Review plan
          |
          +--------------------------+
          |                          |
          v                          v
       Apply flow                Destroy flow
          |                          |
          v                          v
 terraform apply              terraform plan -destroy
                                     |
                                     v
                               Manual approval
                                     |
                                     v
                         terraform apply destroy.tfplan
```

**$:** Terraform compares configuration and state
with AWS, then proposes changes; the pipeline applies only the action
implemented by its stages.

The create/update flow and destroy flow should normally be separate jobs
or require explicit parameters and approvals. Avoid running destroy
automatically on every GitHub push.

## 12. Terraform commands for local troubleshooting

Run commands from the directory containing the Terraform files, with the
correct AWS credentials and backend configured.

``` bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

  -----------------------------------------------------------------------
  Command                             $
  ----------------------------------- -----------------------------------
  `terraform init`                    Initializes providers and connects
                                      to the configured backend.

  `terraform fmt -check -recursive`   Checks Terraform file formatting
                                      without changing files.

  `terraform validate`                Checks configuration syntax and
                                      internal consistency.

  `terraform plan`                    Shows proposed infrastructure
                                      changes without applying them.

  `terraform apply`                   Applies a reviewed plan or asks for
                                      confirmation interactively.

  `terraform plan -destroy`           Previews which state-managed
                                      resources Terraform proposes to
                                      destroy.

  `terraform destroy`                 Plans and asks for confirmation
                                      before destroying state-managed
                                      resources.

  `terraform output`                  Displays outputs recorded in the
                                      current state.

  `terraform state list`              Lists resource addresses tracked by
                                      the current state.
  -----------------------------------------------------------------------

## 13. Safe destroy workflow in Jenkins

Use this procedure when the goal is to remove resources created by
Terraform.

1.  Confirm that `backend.tf` points to the **original, existing S3
    bucket and state key**.

2.  Verify that the Jenkins AWS identity is the intended account and has
    access to the backend and managed resources.

3.  Run `terraform init` successfully.

4.  Generate a destroy plan:

    ``` bash
    terraform plan -destroy -input=false -out=destroy.tfplan
    terraform show -no-color destroy.tfplan
    ```

5.  Review every resource in the plan.

6.  Require a manual Jenkins approval before applying the saved plan:

    ``` bash
    terraform apply -input=false destroy.tfplan
    ```

7.  Verify the resources in AWS and preserve the state bucket until
    cleanup is complete.

**Important:** `terraform destroy` removes resources tracked by the
selected state, not every resource in the AWS account. If the backend
bucket or state file is missing, stop and recover the original state
before attempting destruction. Do not initialize a new empty state and
assume it knows about resources created by a previous run.

The S3 backend bucket is infrastructure used to hold the state;
Terraform does not normally destroy it as part of destroying the
application resources managed by that same backend.


## 14. Final security checklist

-   [ ] S3 state bucket exists, is private, and has versioning enabled.
-   [ ] `backend.tf` uses the exact bucket name and correct region.
-   [ ] Existing Terraform state is preserved and accessible.
-   [ ] Jenkins EC2 instance has the intended IAM role, or the
    configured Jenkins AWS credentials are valid.
-   [ ] IAM permissions follow least privilege.
-   [ ] GitHub PAT is stored only in Jenkins Credentials and has minimal
    repository permissions.
-   [ ] GitHub webhook targets the correct Jenkins endpoint and push
    events are enabled.
-   [ ] Jenkins Pipeline uses the intended repository, credentials,
    branch, and `Jenkinsfile`.
-   [ ] Destruction requires review of the plan and explicit approval.
-   [ ] Secrets, Terraform state, and plan files are not committed to
    GitHub.
-   [ ] Jenkins is protected with appropriate authentication, network
    restrictions, and HTTPS where possible.
