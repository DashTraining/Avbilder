using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure.Communication.Email;
using Azure.Data.Tables;
using Azure.Storage.Blobs;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRouting();

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/me", async (HttpContext context) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null)
    {
        return Results.Problem(
            $"Signed in as '{access.SignedInIdentifier}', but that identity is not in AdminAllowlist.",
            statusCode: StatusCodes.Status403Forbidden);
    }

    return Results.Ok(new { access.Admin.Email, access.Admin.Name });
});

app.MapGet("/api/registrations", async (HttpContext context) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();

    var table = Storage.Tables(app.Configuration).Registrations;
    await table.CreateIfNotExistsAsync();

    var registrations = new List<Dictionary<string, object?>>();
    await foreach (var entity in table.QueryAsync<TableEntity>())
    {
        registrations.Add(EntityProjection.Registration(entity));
    }

    return Results.Ok(registrations
        .OrderByDescending(x => x.GetValueOrDefault("createdUtc")?.ToString())
        .ToArray());
});

app.MapGet("/api/users", async (HttpContext context) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();

    var table = Storage.Tables(app.Configuration).Profiles;
    await table.CreateIfNotExistsAsync();

    var users = new List<Dictionary<string, object?>>();
    await foreach (var entity in table.QueryAsync<TableEntity>())
    {
        users.Add(EntityProjection.Profile(entity));
    }

    return Results.Ok(users
        .OrderBy(x => x.GetValueOrDefault("email")?.ToString())
        .ToArray());
});

app.MapGet("/api/calendar", async (HttpContext context) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();

    var table = Storage.Tables(app.Configuration).Registrations;
    await table.CreateIfNotExistsAsync();

    var items = new List<Dictionary<string, object?>>();
    await foreach (var entity in table.QueryAsync<TableEntity>())
    {
        var preferredDate = entity.GetString("preferredDate");
        if (string.IsNullOrWhiteSpace(preferredDate)) continue;
        items.Add(EntityProjection.Registration(entity));
    }

    return Results.Ok(items
        .OrderBy(x => x.GetValueOrDefault("preferredDate")?.ToString())
        .ToArray());
});

app.MapPost("/api/registrations/{registrationId}/schedule", async (HttpContext context, string registrationId, ScheduleRequest schedule) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();

    var preferredDate = schedule.PreferredDate?.Trim();
    if (string.IsNullOrWhiteSpace(preferredDate)) return Results.BadRequest("Choose a session date.");
    if (!DateOnly.TryParse(preferredDate, out _)) return Results.BadRequest("Use a valid date.");

    var tables = Storage.Tables(app.Configuration);
    var registrations = tables.Registrations;
    await registrations.CreateIfNotExistsAsync();

    var found = new List<TableEntity>();
    await foreach (var entity in registrations.QueryAsync<TableEntity>(x => x.RowKey == Storage.RegistrationRowKey(registrationId)))
    {
        found.Add(entity);
    }

    if (found.Count == 0) return Results.NotFound("Registration not found.");

    var registration = found[0];
    var oldDate = registration.GetString("preferredDate") ?? "";
    var email = registration.GetString("email") ?? "";
    var sessionTitle = registration.GetString("sessionTitle") ?? "photo session";
    var changed = !string.Equals(oldDate, preferredDate, StringComparison.OrdinalIgnoreCase);

    registration["preferredDate"] = preferredDate;
    registration["registrationStatus"] = "Scheduled";
    registration["updatedUtc"] = DateTimeOffset.UtcNow;
    registration["scheduledBy"] = access.Admin.Email;
    await registrations.UpdateEntityAsync(registration, registration.ETag, TableUpdateMode.Replace);

    if (!string.IsNullOrWhiteSpace(email))
    {
        var subject = changed
            ? "Your Avbilder session date was updated"
            : "Your Avbilder session date is approved";
        var intro = changed
            ? $"<p>Your {sessionTitle} date has been updated from {Html(oldDate)} to <strong>{Html(preferredDate)}</strong>.</p>"
            : $"<p>Your {sessionTitle} date is approved for <strong>{Html(preferredDate)}</strong>.</p>";
        var body = $"{intro}<p>Registration ID: {Html(registrationId)}</p>";
        var notification = await Notifications.SendEmailAsync(app.Configuration, tables.Notifications, email, subject, body, changed ? "SessionDateChanged" : "SessionDateApproved", registrationId);
        return Results.Ok(new
        {
            registrationId,
            preferredDate,
            registrationStatus = "Scheduled",
            emailSent = notification.Status == "Succeeded",
            notificationStatus = notification.Status,
            notificationMessage = notification.Message,
            notificationOperationId = notification.OperationId,
            customerEmail = email
        });
    }

    return Results.Ok(new
    {
        registrationId,
        preferredDate,
        registrationStatus = "Scheduled",
        emailSent = false,
        notificationStatus = "Skipped",
        notificationMessage = "Registration does not have a customer email address.",
        customerEmail = ""
    });
});

app.MapDelete("/api/registrations/{registrationId}", async (HttpContext context, string registrationId) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();

    var tables = Storage.Tables(app.Configuration);
    var registrations = tables.Registrations;
    await registrations.CreateIfNotExistsAsync();

    var found = new List<TableEntity>();
    var rowKey = Storage.RegistrationRowKey(registrationId);
    await foreach (var entity in registrations.QueryAsync<TableEntity>(x => x.RowKey == rowKey))
    {
        found.Add(entity);
    }

    if (found.Count == 0) return Results.NotFound("Registration not found.");

    foreach (var entity in found)
    {
        await registrations.DeleteEntityAsync(entity.PartitionKey, entity.RowKey, entity.ETag);
    }

    var registrationPartitionKey = Storage.RegistrationPartitionKey(registrationId);
    await DeletePartitionAsync(tables.Surveys, registrationPartitionKey);
    await DeletePartitionAsync(tables.Previews, registrationPartitionKey);

    var deletedBlobs = 0;
    var container = Storage.PreviewContainer(app.Configuration);
    if (await container.ExistsAsync())
    {
        await foreach (var blob in container.GetBlobsAsync(prefix: $"reg/{registrationId}/"))
        {
            await container.DeleteBlobIfExistsAsync(blob.Name);
            deletedBlobs++;
        }
    }

    return Results.Ok(new { registrationId, deletedRegistrations = found.Count, deletedBlobs });
});

app.MapDelete("/api/users/{email}", async (HttpContext context, string email) =>
{
    var access = await AdminContext.GetAccessAsync(context, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();

    var table = Storage.Tables(app.Configuration).Profiles;
    await table.CreateIfNotExistsAsync();

    var partitionKey = Storage.CustomerPartitionKey(email);
    try
    {
        var deleted = await table.DeleteEntityAsync(partitionKey, "PROFILE", Azure.ETag.All);
        return Results.Ok(new { email, deleted = deleted.Status is >= 200 and < 300 });
    }
    catch (Azure.RequestFailedException ex) when (ex.Status == StatusCodes.Status404NotFound)
    {
        return Results.NotFound("User profile not found.");
    }
});

app.MapPost("/api/registrations/{registrationId}/previews", async (HttpRequest request, string registrationId) =>
{
    var access = await AdminContext.GetAccessAsync(request.HttpContext, app.Configuration);
    if (!access.IsSignedIn) return Results.Unauthorized();
    if (access.Admin is null) return Results.Forbid();
    var admin = access.Admin;
    if (!request.HasFormContentType) return Results.BadRequest("Upload JPEG files as multipart/form-data.");

    var files = request.Form.Files;
    if (files.Count == 0) return Results.BadRequest("No files were uploaded.");

    var tables = Storage.Tables(app.Configuration);
    var registrations = tables.Registrations;
    await registrations.CreateIfNotExistsAsync();

    var found = new List<TableEntity>();
    var rowKey = Storage.RegistrationRowKey(registrationId);
    await foreach (var entity in registrations.QueryAsync<TableEntity>(x => x.RowKey == rowKey))
    {
        found.Add(entity);
    }

    if (found.Count == 0) return Results.NotFound("Registration not found.");

    var container = Storage.PreviewContainer(app.Configuration);
    await container.CreateIfNotExistsAsync();

    var uploaded = 0;
    foreach (var file in files)
    {
        if (!IsJpeg(file.FileName, file.ContentType)) continue;

        var safeName = Storage.SafeBlobFileName(file.FileName);
        var blobName = $"reg/{registrationId}/{DateTimeOffset.UtcNow:yyyyMMddHHmmssfff}-{uploaded + 1:00}-{safeName}";
        var blob = container.GetBlobClient(blobName);

        await using var stream = file.OpenReadStream();
        await blob.UploadAsync(stream, overwrite: true);
        uploaded++;
    }

    if (uploaded == 0) return Results.BadRequest("No JPEG files were uploaded.");

    var previewCount = 0;
    await foreach (var blob in container.GetBlobsAsync(prefix: $"reg/{registrationId}/"))
    {
        if (IsJpeg(blob.Name, null)) previewCount++;
    }

    var registration = found[0];
    registration["previewStatus"] = "Ready";
    registration["previewCount"] = previewCount;
    registration["updatedUtc"] = DateTimeOffset.UtcNow;
    await registrations.UpdateEntityAsync(registration, registration.ETag, TableUpdateMode.Replace);

    var previews = tables.Previews;
    await previews.CreateIfNotExistsAsync();
    await previews.UpsertEntityAsync(new TableEntity(Storage.RegistrationPartitionKey(registrationId), "PREVIEW")
    {
        ["userId"] = registration.GetString("userId") ?? "",
        ["prefix"] = $"reg/{registrationId}/",
        ["previewCount"] = previewCount,
        ["publishedUtc"] = DateTimeOffset.UtcNow,
        ["status"] = "Ready",
        ["publishedBy"] = admin.Email
    });

    return Results.Ok(new { registrationId, uploaded, previewCount, status = "Ready" });
});

app.MapFallbackToFile("index.html");

app.Run();

static bool IsJpeg(string name, string? contentType) =>
    name.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
    || name.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase)
    || string.Equals(contentType, "image/jpeg", StringComparison.OrdinalIgnoreCase);

static async Task DeletePartitionAsync(TableClient table, string partitionKey)
{
    await table.CreateIfNotExistsAsync();
    var entities = new List<TableEntity>();
    await foreach (var entity in table.QueryAsync<TableEntity>(x => x.PartitionKey == partitionKey))
    {
        entities.Add(entity);
    }

    foreach (var entity in entities)
    {
        await table.DeleteEntityAsync(entity.PartitionKey, entity.RowKey, entity.ETag);
    }
}

static string Html(string? value) => System.Net.WebUtility.HtmlEncode(value ?? "");

internal sealed record ScheduleRequest(string? PreferredDate);

internal sealed record AdminUser(string Email, string Name);
internal sealed record AdminAccess(bool IsSignedIn, string? SignedInIdentifier, AdminUser? Admin);

internal static class AdminContext
{
    private static readonly string[] EmailClaimTypes =
    [
        "preferred_username",
        "email",
        "emails",
        "upn",
        "unique_name",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
    ];

    public static async Task<AdminAccess> GetAccessAsync(HttpContext context, IConfiguration configuration)
    {
        var headers = context.Request.Headers;
        var principal = ParseClientPrincipal(GetHeader(headers, "X-MS-CLIENT-PRINCIPAL"));
        var candidates = CandidateIdentifiers(headers, principal).ToArray();
        if (candidates.Length == 0) return new AdminAccess(false, null, null);

        var table = Storage.Tables(configuration).Admins;
        await table.CreateIfNotExistsAsync();

        foreach (var candidate in candidates)
        {
            var admin = await table.GetEntityIfExistsAsync<TableEntity>("ADMIN", NormalizeEmail(candidate));
            if (!admin.HasValue) continue;

            var adminEntity = admin.Value!;
            if (adminEntity.GetBoolean("Enabled") != true) continue;

            var adminEmail = adminEntity.GetString("Email") ?? NormalizeEmail(candidate);
            return new AdminAccess(true, candidate, new AdminUser(adminEmail, adminEmail));
        }

        return new AdminAccess(true, candidates[0], null);
    }

    private static string? GetHeader(IHeaderDictionary headers, string name) =>
        headers.TryGetValue(name, out var values) ? values.FirstOrDefault() : null;

    private static IEnumerable<string> CandidateIdentifiers(IHeaderDictionary headers, ClientPrincipal? principal)
    {
        foreach (var claimType in EmailClaimTypes)
        {
            foreach (var value in principal?.Claims?.Where(claim => string.Equals(claim.Type, claimType, StringComparison.OrdinalIgnoreCase)).Select(claim => claim.Value) ?? [])
            {
                if (LooksUsable(value)) yield return value!;
            }
        }

        if (LooksUsable(principal?.UserDetails)) yield return principal!.UserDetails!;
        if (LooksUsable(GetHeader(headers, "X-MS-CLIENT-PRINCIPAL-NAME"))) yield return GetHeader(headers, "X-MS-CLIENT-PRINCIPAL-NAME")!;
        if (LooksUsable(GetHeader(headers, "X-MS-CLIENT-PRINCIPAL-ID"))) yield return GetHeader(headers, "X-MS-CLIENT-PRINCIPAL-ID")!;
    }

    private static bool LooksUsable(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Length < 256;

    private static ClientPrincipal? ParseClientPrincipal(string? encoded)
    {
        if (string.IsNullOrWhiteSpace(encoded)) return null;
        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(encoded));
            return JsonSerializer.Deserialize<ClientPrincipal>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch
        {
            return null;
        }
    }

    private static string NormalizeEmail(string email) => email.Trim().ToLowerInvariant();
}

internal sealed class ClientPrincipal
{
    [JsonPropertyName("userDetails")]
    public string? UserDetails { get; set; }

    [JsonPropertyName("claims")]
    public ClientPrincipalClaim[] Claims { get; set; } = [];
}

internal sealed class ClientPrincipalClaim
{
    [JsonPropertyName("typ")]
    public string? Type { get; set; }

    [JsonPropertyName("val")]
    public string? Value { get; set; }
}

internal sealed record StorageTables(
    TableClient Profiles,
    TableClient Registrations,
    TableClient Surveys,
    TableClient Previews,
    TableClient Admins,
    TableClient Notifications);

internal static class Storage
{
    public static StorageTables Tables(IConfiguration configuration)
    {
        var connectionString = Required(configuration, "DATA_STORAGE_CONNECTION_STRING");
        return new StorageTables(
            new TableClient(connectionString, Setting(configuration, "TABLE_CUSTOMER_PROFILES", "CustomerProfiles")),
            new TableClient(connectionString, Setting(configuration, "TABLE_SESSION_REGISTRATIONS", "SessionRegistrations")),
            new TableClient(connectionString, Setting(configuration, "TABLE_SURVEY_RESPONSES", "SurveyResponses")),
            new TableClient(connectionString, Setting(configuration, "TABLE_PREVIEW_SETS", "PreviewSets")),
            new TableClient(connectionString, Setting(configuration, "TABLE_ADMIN_ALLOWLIST", "AdminAllowlist")),
            new TableClient(connectionString, Setting(configuration, "TABLE_NOTIFICATION_LOG", "NotificationLog")));
    }

    public static BlobContainerClient PreviewContainer(IConfiguration configuration)
    {
        var connectionString = Required(configuration, "DATA_STORAGE_CONNECTION_STRING");
        var container = Setting(configuration, "BLOB_CONTAINER_PREVIEWS", "previews");
        return new BlobContainerClient(connectionString, container);
    }

    public static string CustomerPartitionKey(string email) => $"EMAIL_{EncodeKeySegment(NormalizeEmail(email))}";
    public static string RegistrationPartitionKey(string registrationId) => $"REG_{registrationId}";
    public static string RegistrationRowKey(string registrationId) => $"REG_{registrationId}";

    public static string SafeBlobFileName(string name)
    {
        var fileName = Path.GetFileName(name);
        var cleaned = new string(fileName.Select(ch => char.IsLetterOrDigit(ch) || ch is '.' or '-' or '_' ? ch : '-').ToArray());
        return string.IsNullOrWhiteSpace(cleaned) ? "preview.jpg" : cleaned;
    }

    private static string Required(IConfiguration configuration, string name) =>
        configuration[name] ?? throw new InvalidOperationException($"Missing setting: {name}");

    private static string Setting(IConfiguration configuration, string name, string defaultValue) =>
        configuration[name] ?? defaultValue;

    private static string NormalizeEmail(string email) => email.Trim().ToLowerInvariant();

    private static string EncodeKeySegment(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}

internal sealed record NotificationResult(string Status, string Message, string OperationId);

internal static class Notifications
{
    public static async Task<NotificationResult> SendEmailAsync(IConfiguration configuration, TableClient notificationLog, string to, string subject, string html, string workflow, string registrationId)
    {
        var id = Guid.NewGuid().ToString("n");
        var now = DateTimeOffset.UtcNow;
        var connectionString = configuration["ACS_CONNECTION_STRING"];
        var sender = configuration["ACS_EMAIL_SENDER"];

        if (string.IsNullOrWhiteSpace(connectionString) || string.IsNullOrWhiteSpace(sender))
        {
            var message = "ACS settings are not configured.";
            await RecordAsync(notificationLog, id, to, subject, workflow, registrationId, "Skipped", message, "", now);
            return new NotificationResult("Skipped", message, "");
        }

        try
        {
            var client = new EmailClient(connectionString);
            // Wait for the ACS operation result so the admin UI can show a meaningful send status.
            var operation = await client.SendAsync(Azure.WaitUntil.Completed, sender, to, subject, htmlContent: html);
            var result = operation.Value;
            var status = result.Status.ToString();
            var message = $"ACS send operation {status} for {to}.";
            await RecordAsync(notificationLog, id, to, subject, workflow, registrationId, status, message, operation.Id, now);
            return new NotificationResult(status, message, operation.Id);
        }
        catch (Exception ex)
        {
            await RecordAsync(notificationLog, id, to, subject, workflow, registrationId, "Failed", ex.Message, "", now);
            return new NotificationResult("Failed", ex.Message, "");
        }
    }

    private static async Task RecordAsync(TableClient table, string id, string to, string subject, string workflow, string registrationId, string status, string message, string operationId, DateTimeOffset now)
    {
        try
        {
            await table.CreateIfNotExistsAsync();
            await table.AddEntityAsync(new TableEntity($"WORKFLOW_{workflow}", $"NOTIFY_{id}")
            {
                ["to"] = to,
                ["subject"] = subject,
                ["registrationId"] = registrationId,
                ["status"] = status,
                ["message"] = message,
                ["operationId"] = operationId,
                ["createdUtc"] = now
            });
        }
        catch
        {
            // Notifications should not block admin workflow in the demo.
        }
    }
}

internal static class EntityProjection
{
    public static Dictionary<string, object?> Registration(TableEntity entity) => new()
    {
        ["registrationId"] = entity.GetString("registrationId"),
        ["email"] = entity.GetString("email"),
        ["sessionId"] = entity.GetString("sessionId"),
        ["sessionTitle"] = entity.GetString("sessionTitle"),
        ["preferredDate"] = entity.GetString("preferredDate"),
        ["registrationStatus"] = entity.GetString("registrationStatus"),
        ["surveyStatus"] = entity.GetString("surveyStatus"),
        ["previewStatus"] = entity.GetString("previewStatus"),
        ["previewCount"] = entity.ContainsKey("previewCount") ? entity.GetInt32("previewCount") : 0,
        ["createdUtc"] = entity.ContainsKey("createdUtc") ? entity.GetDateTimeOffset("createdUtc") : null,
        ["updatedUtc"] = entity.ContainsKey("updatedUtc") ? entity.GetDateTimeOffset("updatedUtc") : null
    };

    public static Dictionary<string, object?> Profile(TableEntity entity) => new()
    {
        ["displayName"] = entity.GetString("displayName"),
        ["email"] = entity.GetString("email"),
        ["phone"] = entity.GetString("phone"),
        ["identityProvider"] = entity.GetString("identityProvider"),
        ["lastSeenUtc"] = entity.ContainsKey("lastSeenUtc") ? entity.GetDateTimeOffset("lastSeenUtc") : null
    };
}
