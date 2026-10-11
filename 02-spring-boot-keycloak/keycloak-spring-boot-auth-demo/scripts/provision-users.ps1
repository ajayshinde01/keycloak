<#
.SYNOPSIS
  Provisions the demo realm, client, roles and users using Keycloak's
  Admin CLI (kcadm.sh), the way you would against a real Keycloak
  instance that has no pre-built realm export to import.

  Safe to re-run: anything that already exists is skipped.

  For Windows (PowerShell). macOS/Linux users should use
  scripts/provision-users.sh instead.

.EXAMPLE
  docker compose up -d
  .\scripts\provision-users.ps1
#>

$Container = "keycloak-demo"
$Kcadm = "/opt/keycloak/bin/kcadm.sh"
$AdminUser = "admin"
$AdminPassword = "admin"
$Realm = "demo"
$ClientId = "spring-boot-api"

# Demo users. Change these to provision your own users.
$AppUser = "ajay"
$AppUserPassword = "ajay123"
$AppUserEmail = "ajay@example.com"
$AppUserFirstName = "Ajay"
$AppUserLastName = "User"

# Application admin inside the demo realm, not the Keycloak bootstrap admin.
$AppAdmin = "admin"
$AppAdminPassword = "admin123"
$AppAdminEmail = "admin@example.com"
$AppAdminFirstName = "Admin"
$AppAdminLastName = "User"

# Native stderr output (kcadm.sh logs informational lines there) must not be
# redirected: PowerShell 5.1 wraps redirected stderr lines in a terminating
# NativeCommandError even on success. Check $LASTEXITCODE instead.
function Invoke-Kcadm {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$KcadmArgs)
    & docker exec $Container $Kcadm @KcadmArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "kcadm.sh failed: $($KcadmArgs -join ' ')"
    }
}

# Returns $true if the kcadm "get" query returns a non-empty result.
function Test-KcadmExists {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$KcadmArgs)
    # A missing resource is the expected case here, so its "not found" stderr is discarded.
    $out = (& docker exec $Container $Kcadm get @KcadmArgs 2>$null) -join ""
    if ($LASTEXITCODE -ne 0) { return $false }
    $out = $out -replace '\s', ''
    return ($out -ne "" -and $out -ne "[]")
}

function New-DemoUser {
    param(
        [string]$Username,
        [string]$Email,
        [string]$FirstName,
        [string]$LastName,
        [string]$Password,
        [string[]]$Roles
    )
    if (Test-KcadmExists users -r $Realm -q "username=$Username" -q "exact=true") {
        Write-Host "User '$Username' already exists, skipping create."
    } else {
        Write-Host "Creating user '$Username'..."
        Invoke-Kcadm create users -r $Realm -s "username=$Username" -s "enabled=true" -s "email=$Email" -s "emailVerified=true" -s "firstName=$FirstName" -s "lastName=$LastName"
    }
    Invoke-Kcadm set-password -r $Realm --username $Username --new-password $Password
    foreach ($role in $Roles) {
        Write-Host "  Assigning realm role $role to '$Username'"
        Invoke-Kcadm add-roles -r $Realm --uusername $Username --rolename $role
    }
}

Write-Host "Waiting for Keycloak to accept admin CLI logins..."
$loggedIn = $false
while (-not $loggedIn) {
    & docker exec $Container $Kcadm config credentials --server http://localhost:8080 --realm master --user $AdminUser --password $AdminPassword | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $loggedIn = $true
    } else {
        Start-Sleep -Seconds 2
    }
}

if (Test-KcadmExists "realms/$Realm") {
    Write-Host "Realm '$Realm' already exists, skipping create."
} else {
    Write-Host "Creating realm '$Realm'..."
    Invoke-Kcadm create realms -s "realm=$Realm" -s "enabled=true" -s "displayName=Keycloak Spring Boot Demo"
}

$roles = [ordered]@{ "USER" = "Regular application user"; "ADMIN" = "Application administrator" }
foreach ($role in $roles.Keys) {
    if (Test-KcadmExists "roles/$role" -r $Realm) {
        Write-Host "Realm role $role already exists, skipping create."
    } else {
        Write-Host "Creating realm role $role..."
        Invoke-Kcadm create roles -r $Realm -s "name=$role" -s "description=$($roles[$role])"
    }
}

if (Test-KcadmExists clients -r $Realm -q "clientId=$ClientId") {
    Write-Host "Client '$ClientId' already exists, skipping create."
} else {
    Write-Host "Creating client '$ClientId'..."
    Invoke-Kcadm create clients -r $Realm `
        -s "clientId=$ClientId" `
        -s "name=Spring Boot API" `
        -s "enabled=true" `
        -s "publicClient=true" `
        -s "protocol=openid-connect" `
        -s "directAccessGrantsEnabled=true" `
        -s "standardFlowEnabled=false" `
        -s "serviceAccountsEnabled=false" `
        -s "fullScopeAllowed=true"
}

New-DemoUser -Username $AppUser -Email $AppUserEmail -FirstName $AppUserFirstName -LastName $AppUserLastName -Password $AppUserPassword -Roles @("USER")
New-DemoUser -Username $AppAdmin -Email $AppAdminEmail -FirstName $AppAdminFirstName -LastName $AppAdminLastName -Password $AppAdminPassword -Roles @("USER", "ADMIN")

Write-Host "Done. Realm '$Realm' is provisioned with client '$ClientId' and users $AppUser/$AppAdmin."
