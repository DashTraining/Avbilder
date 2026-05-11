using System.Net;
using Azure.Data.Tables;
using Azure.Storage.Blobs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace Avbilder.Api;

public sealed class PreviewFunctions
{
    [Function("Previews")]
    public async Task<HttpResponseData> Previews([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "previews")] HttpRequestData req)
    {
        var principal = await Support.GetPrincipalAsync(req);
        var email = Support.PrincipalEmail(principal);
        if (email is null) return await Support.TextAsync(req, "Authentication required.", HttpStatusCode.Unauthorized);

        var regs = Support.Table("TABLE_SESSION_REGISTRATIONS", "SessionRegistrations");
        await regs.CreateIfNotExistsAsync();
        var list = new List<object>();
        await foreach (var e in regs.QueryAsync<TableEntity>(x => x.PartitionKey == Support.CustomerPartitionKey(email)))
        {
            if (e.GetString("previewStatus") != "Ready") continue;
            list.Add(new {
                registrationId = e.GetString("registrationId"),
                sessionTitle = e.GetString("sessionTitle"),
                previewCount = e.ContainsKey("previewCount") ? e.GetInt32("previewCount") : 20
            });
        }
        return await Support.JsonAsync(req, list);
    }

    [Function("PreviewAccess")]
    public async Task<HttpResponseData> PreviewAccess([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "previews/{registrationId}/access")] HttpRequestData req, string registrationId)
    {
        var principal = await Support.GetPrincipalAsync(req);
        var email = Support.PrincipalEmail(principal);
        if (email is null) return await Support.TextAsync(req, "Authentication required.", HttpStatusCode.Unauthorized);

        var regs = Support.Table("TABLE_SESSION_REGISTRATIONS", "SessionRegistrations");
        var entity = await regs.GetEntityIfExistsAsync<TableEntity>(Support.CustomerPartitionKey(email), Support.RegistrationRowKey(registrationId));
        if (!entity.HasValue) return await Support.TextAsync(req, "Registration not found.", HttpStatusCode.NotFound);
        var registration = entity.Value!;
        if (registration.GetString("previewStatus") != "Ready") return await Support.TextAsync(req, "Previews are not ready.", HttpStatusCode.Conflict);

        var container = Support.PreviewContainer();
        var urls = new List<string>();
        await foreach (var blob in container.GetBlobsAsync(prefix: $"reg/{registrationId}/"))
        {
            if (!blob.Name.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) && !blob.Name.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase)) continue;
            urls.Add(Support.CreateReadSas(container.GetBlobClient(blob.Name), TimeSpan.FromMinutes(15)).ToString());
        }
        return await Support.JsonAsync(req, new PreviewAccessResponse(registrationId, urls));
    }

    [Function("PublishPreview")]
    public async Task<HttpResponseData> PublishPreview([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "admin/previews/{registrationId}/publish")] HttpRequestData req, string registrationId)
    {
        return await PublishPreviewCore(req, registrationId);
    }

    [Function("PublishPreviewLegacy")]
    public async Task<HttpResponseData> PublishPreviewLegacy([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "admin/publish-preview/{registrationId}")] HttpRequestData req, string registrationId)
    {
        return await PublishPreviewCore(req, registrationId);
    }

    private static async Task<HttpResponseData> PublishPreviewCore(HttpRequestData req, string registrationId)
    {
        var principal = await Support.GetPrincipalAsync(req);
        var email = Support.PrincipalEmail(principal);
        if (email is null) return await Support.TextAsync(req, "Authentication required.", HttpStatusCode.Unauthorized);

        var admins = Support.Table("TABLE_ADMIN_ALLOWLIST", "AdminAllowlist");
        await admins.CreateIfNotExistsAsync();
        var admin = await admins.GetEntityIfExistsAsync<TableEntity>("ADMIN", email);
        if (!admin.HasValue) return await Support.TextAsync(req, "Admin access required.", HttpStatusCode.Forbidden);
        var adminEntity = admin.Value!;
        if (adminEntity.GetBoolean("Enabled") != true) return await Support.TextAsync(req, "Admin access required.", HttpStatusCode.Forbidden);

        var regs = Support.Table("TABLE_SESSION_REGISTRATIONS", "SessionRegistrations");
        var found = new List<TableEntity>();
        await foreach (var e in regs.QueryAsync<TableEntity>(x => x.RowKey == Support.RegistrationRowKey(registrationId))) found.Add(e);
        if (found.Count == 0) return await Support.TextAsync(req, "Registration not found.", HttpStatusCode.NotFound);
        var reg = found[0];

        var container = Support.PreviewContainer();
        var count = 0;
        await foreach (var blob in container.GetBlobsAsync(prefix: $"reg/{registrationId}/"))
        {
            if (blob.Name.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) || blob.Name.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase)) count++;
        }

        reg["previewStatus"] = "Ready";
        reg["previewCount"] = count;
        reg["updatedUtc"] = DateTimeOffset.UtcNow;
        await regs.UpdateEntityAsync(reg, reg.ETag, TableUpdateMode.Replace);

        var previews = Support.Table("TABLE_PREVIEW_SETS", "PreviewSets");
        await previews.CreateIfNotExistsAsync();
        await previews.UpsertEntityAsync(new TableEntity(Support.RegistrationPartitionKey(registrationId), "PREVIEW")
        {
            ["userId"] = reg.GetString("userId") ?? "",
            ["prefix"] = $"reg/{registrationId}/",
            ["previewCount"] = count,
            ["publishedUtc"] = DateTimeOffset.UtcNow,
            ["status"] = "Ready"
        });

        var customerEmail = reg.GetString("email");
        if (!string.IsNullOrWhiteSpace(customerEmail))
        {
            var baseUrl = Environment.GetEnvironmentVariable("APP_PUBLIC_BASE_URL") ?? "https://www.avbilder.no";
            await Support.SendEmailAsync(customerEmail, "Your Avbilder previews are ready", $"<p>Your previews are ready.</p><p>Sign in at {baseUrl}/portal/previews/</p>", "PreviewReady", registrationId);
        }

        return await Support.JsonAsync(req, new { registrationId, previewCount = count, status = "Ready" });
    }
}
