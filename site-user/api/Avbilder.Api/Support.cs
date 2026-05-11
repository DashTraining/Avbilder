using System.Net;
using System.Text;
using System.Text.Json;
using Azure.Communication.Email;
using Azure.Data.Tables;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using Microsoft.Azure.Functions.Worker.Http;

namespace Avbilder.Api;

internal static class Support
{
    public static string RequireSetting(string name) =>
        Environment.GetEnvironmentVariable(name) ?? throw new InvalidOperationException($"Missing setting: {name}");

    public static string RequireAnySetting(params string[] names)
    {
        foreach (var name in names)
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrWhiteSpace(value)) return value;
        }

        throw new InvalidOperationException($"Missing setting: {string.Join(" or ", names)}");
    }

    public static string TableName(string settingName, string defaultName) =>
        Environment.GetEnvironmentVariable(settingName) ?? defaultName;

    public static string NormalizeEmail(string email) => email.Trim().ToLowerInvariant();

    public static string CustomerPartitionKey(string email) => $"EMAIL_{EncodeKeySegment(NormalizeEmail(email))}";

    public static string RegistrationPartitionKey(string registrationId) => $"REG_{registrationId}";

    public static string RegistrationRowKey(string registrationId) => $"REG_{registrationId}";

    public static string WorkflowPartitionKey(string workflow) => $"WORKFLOW_{workflow}";

    public static string NotificationRowKey(string notificationId) => $"NOTIFY_{notificationId}";

    private static string EncodeKeySegment(string value) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(value))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    public static string? PrincipalEmail(ClientPrincipal? principal)
    {
        // SWA auth providers differ in where they place the email. Prefer explicit email claims.
        var candidates = new[]
        {
            principal?.UserDetails,
            Claim(principal, "preferred_username"),
            Claim(principal, "email"),
            Claim(principal, "emails"),
            Claim(principal, "upn"),
            Claim(principal, "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress")
        };

        var value = candidates.FirstOrDefault(x => !string.IsNullOrWhiteSpace(x) && x.Contains('@'));
        return string.IsNullOrWhiteSpace(value) ? null : NormalizeEmail(value);
    }

    private static string? Claim(ClientPrincipal? principal, string type) =>
        principal?.Claims.FirstOrDefault(claim => string.Equals(claim.Type, type, StringComparison.OrdinalIgnoreCase))?.Value;

    public static Task<ClientPrincipal?> GetPrincipalAsync(HttpRequestData req)
    {
        if (!req.Headers.TryGetValues("x-ms-client-principal", out var values)) return Task.FromResult<ClientPrincipal?>(null);
        var encoded = values.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(encoded)) return Task.FromResult<ClientPrincipal?>(null);
        var json = Encoding.UTF8.GetString(Convert.FromBase64String(encoded));
        var principal = JsonSerializer.Deserialize<ClientPrincipal>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return Task.FromResult(principal);
    }

    public static async Task<HttpResponseData> JsonAsync<T>(HttpRequestData req, T payload, HttpStatusCode status = HttpStatusCode.OK)
    {
        var res = req.CreateResponse(status);
        res.Headers.Add("content-type", "application/json");
        await res.WriteStringAsync(JsonSerializer.Serialize(payload, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        return res;
    }

    public static async Task<HttpResponseData> TextAsync(HttpRequestData req, string text, HttpStatusCode status)
    {
        var res = req.CreateResponse(status);
        await res.WriteStringAsync(text);
        return res;
    }

    public static TableClient Table(string tableName)
    {
        var conn = RequireAnySetting("DATA_STORAGE_CONNECTION_STRING", "STORAGE_CONNECTION_STRING");
        return new TableClient(conn, tableName);
    }

    public static TableClient Table(string settingName, string defaultName) =>
        Table(TableName(settingName, defaultName));

    public static BlobContainerClient PreviewContainer()
    {
        var conn = RequireAnySetting("DATA_STORAGE_CONNECTION_STRING", "STORAGE_CONNECTION_STRING");
        var container = Environment.GetEnvironmentVariable("BLOB_CONTAINER_PREVIEWS")
            ?? Environment.GetEnvironmentVariable("PREVIEW_CONTAINER")
            ?? "previews";
        return new BlobContainerClient(conn, container);
    }

    public static Uri CreateReadSas(BlobClient blob, TimeSpan lifetime)
    {
        if (!blob.CanGenerateSasUri)
            throw new InvalidOperationException("Blob client cannot generate SAS. Use a connection string with account key for the demo implementation.");

        var builder = new BlobSasBuilder
        {
            BlobContainerName = blob.BlobContainerName,
            BlobName = blob.Name,
            Resource = "b",
            ExpiresOn = DateTimeOffset.UtcNow.Add(lifetime)
        };
        builder.SetPermissions(BlobSasPermissions.Read);
        return blob.GenerateSasUri(builder);
    }

    public static async Task<EmailSendResult> SendEmailAsync(string to, string subject, string html, string workflow, string? registrationId = null)
    {
        var notificationId = Guid.NewGuid().ToString("n");
        var now = DateTimeOffset.UtcNow;
        var conn = Environment.GetEnvironmentVariable("ACS_CONNECTION_STRING");
        var sender = Environment.GetEnvironmentVariable("ACS_EMAIL_SENDER");

        if (string.IsNullOrWhiteSpace(conn) || string.IsNullOrWhiteSpace(sender))
        {
            var skipped = new EmailSendResult(notificationId, "Skipped", "ACS settings are not configured.", "");
            await RecordNotificationAsync(notificationId, to, subject, workflow, registrationId, skipped.Status, skipped.Message, skipped.OperationId, now);
            return skipped;
        }

        try
        {
            var client = new EmailClient(conn);
            // Wait for the ACS operation result so NotificationLog can be correlated with ACS diagnostics.
            var operation = await client.SendAsync(Azure.WaitUntil.Completed, sender, to, subject, htmlContent: html);
            var result = operation.Value;
            var status = result.Status.ToString();
            var message = $"ACS send operation {status} for {to}.";
            var sent = new EmailSendResult(notificationId, status, message, operation.Id);
            await RecordNotificationAsync(notificationId, to, subject, workflow, registrationId, sent.Status, sent.Message, sent.OperationId, now);
            return sent;
        }
        catch (Exception ex)
        {
            var failed = new EmailSendResult(notificationId, "Failed", ex.Message, "");
            await RecordNotificationAsync(notificationId, to, subject, workflow, registrationId, failed.Status, failed.Message, failed.OperationId, now);
            return failed;
        }
    }

    private static async Task RecordNotificationAsync(string id, string to, string subject, string workflow, string? registrationId, string status, string message, string operationId, DateTimeOffset now)
    {
        try
        {
            var table = Table("TABLE_NOTIFICATION_LOG", "NotificationLog");
            await table.CreateIfNotExistsAsync();
            await table.AddEntityAsync(new TableEntity(WorkflowPartitionKey(workflow), NotificationRowKey(id))
            {
                ["to"] = to,
                ["subject"] = subject,
                ["registrationId"] = registrationId ?? "",
                ["status"] = status,
                ["message"] = message,
                ["operationId"] = operationId,
                ["createdUtc"] = now
            });
        }
        catch
        {
            // Email should not make the customer-facing flow fail in the low-cost demo.
        }
    }
}

internal sealed record EmailSendResult(string NotificationId, string Status, string Message, string OperationId);
