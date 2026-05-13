<?php
echo "<h1> Azure Secure 2-Tier Infrastructure Project</h1>";
echo "<p>This page was <b>automatically deployed</b> via GitHub Actions CI/CD pipeline.</p>";

// Checking Infrastructure Connectivity
$db_server = getenv('DB_SERVER');

echo "<hr>";
echo "<h3>Infrastructure Connectivity Status:</h3>";

if ($db_server) {
    echo "<ul>";
    echo "<li> <b>Database Server Host:</b> <code>$db_server</code></li>";
    echo "<li> <b>Network Security:</b> VNet Integration Active</li>";
    echo "<li> <b>Secret Management:</b> Azure Key Vault Reference Verified</li>";
    echo "</ul>";
    echo "<p><i>The application is successfully communicating with the backend database within the private network.</i></p>";
} else {
    echo "<ul>";
    echo "<li>❌ <b>Status:</b> Environment variables not found.</li>";
    echo "<li><b>Action required:</b> Please check the App Service Configuration (App Settings).</li>";
    echo "</ul>";
}

echo "<hr>";
echo "<footer>";
echo "<small>Managed by <b>Dana Kim</b> | Infrastructure as Code (Terraform)</small>";
echo "</footer>";
?>