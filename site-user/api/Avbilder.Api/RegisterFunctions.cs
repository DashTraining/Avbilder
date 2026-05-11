using System.Net;
using System.Text.Json;
using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace Avbilder.Api;

public sealed class RegisterFunctions
{
    [Function("CreateRegistration")]
    public async Task<HttpResponseData> Register([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "registrations")] HttpRequestData req)
    {
        var principal = await Support.GetPrincipalAsync(req);

        var request = await JsonSerializer.DeserializeAsync<RegistrationRequest>(req.Body, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (request is null || string.IsNullOrWhiteSpace(request.SessionId) || string.IsNullOrWhiteSpace(request.AttendeeName) || string.IsNullOrWhiteSpace(request.Email))
            return await Support.TextAsync(req, "Missing registration data.", HttpStatusCode.BadRequest);

        var registrationId = Guid.NewGuid().ToString("n");
        var now = DateTimeOffset.UtcNow;
        // Once the register page is protected, the signed-in SWA identity is the durable customer key.
        var email = Support.PrincipalEmail(principal) ?? Support.NormalizeEmail(request.Email);
        var sessionTitle = request.SessionId switch
        {
            "portrait" => "Portrait session",
            "family" => "Family mini-session",
            "business" => "Business headshots",
            _ => request.SessionId
        };

        var profiles = Support.Table("TABLE_CUSTOMER_PROFILES", "CustomerProfiles");
        var regs = Support.Table("TABLE_SESSION_REGISTRATIONS", "SessionRegistrations");
        var surveys = Support.Table("TABLE_SURVEY_RESPONSES", "SurveyResponses");

        await profiles.CreateIfNotExistsAsync();
        await regs.CreateIfNotExistsAsync();
        await surveys.CreateIfNotExistsAsync();

        await profiles.UpsertEntityAsync(new TableEntity(Support.CustomerPartitionKey(email), "PROFILE")
        {
            ["displayName"] = request.AttendeeName,
            ["email"] = email,
            ["phone"] = request.Phone ?? "",
            ["identityProvider"] = principal?.IdentityProvider ?? "none",
            ["userId"] = principal?.UserId ?? "",
            ["lastSeenUtc"] = now
        });

        await regs.AddEntityAsync(new TableEntity(Support.CustomerPartitionKey(email), Support.RegistrationRowKey(registrationId))
        {
            ["registrationId"] = registrationId,
            ["userId"] = principal?.UserId ?? "",
            ["email"] = email,
            ["sessionId"] = request.SessionId,
            ["sessionTitle"] = sessionTitle,
            ["preferredDate"] = request.PreferredDate ?? "",
            ["registrationStatus"] = "Needs Approval",
            ["surveyStatus"] = "Submitted",
            ["previewStatus"] = "PreviewsNotReady",
            ["createdUtc"] = now,
            ["updatedUtc"] = now
        });

        await surveys.UpsertEntityAsync(new TableEntity(Support.RegistrationPartitionKey(registrationId), "SURVEY")
        {
            ["userId"] = principal?.UserId ?? "",
            ["email"] = email,
            ["preferredStyle"] = request.PreferredStyle ?? "",
            ["participantsCount"] = request.ParticipantsCount,
            ["usagePurpose"] = request.UsagePurpose ?? "",
            ["notes"] = request.Notes ?? "",
            ["submittedUtc"] = now
        });

        var confirmationEmail = await Support.SendEmailAsync(email, "Avbilder registration received", $"<p>Your {sessionTitle} registration has been received.</p><p>Reference: {registrationId}</p>", "Registration", registrationId);

        return await Support.JsonAsync(req, new { registrationId, sessionTitle, status = "Needs Approval", confirmationEmail });
    }

    [Function("Registrations")]
    public async Task<HttpResponseData> Registrations([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "registrations")] HttpRequestData req)
    {
        var principal = await Support.GetPrincipalAsync(req);
        var email = Support.PrincipalEmail(principal);
        if (email is null) return await Support.TextAsync(req, "Authentication required.", HttpStatusCode.Unauthorized);

        var regs = Support.Table("TABLE_SESSION_REGISTRATIONS", "SessionRegistrations");
        await regs.CreateIfNotExistsAsync();
        var list = new List<object>();
        await foreach (var e in regs.QueryAsync<TableEntity>(x => x.PartitionKey == Support.CustomerPartitionKey(email)))
        {
            list.Add(new {
                registrationId = e.GetString("registrationId"),
                sessionTitle = e.GetString("sessionTitle"),
                preferredDate = e.GetString("preferredDate"),
                registrationStatus = e.GetString("registrationStatus"),
                surveyStatus = e.GetString("surveyStatus"),
                previewStatus = e.GetString("previewStatus")
            });
        }
        return await Support.JsonAsync(req, list);
    }

    [Function("SubmitSurvey")]
    public async Task<HttpResponseData> SubmitSurvey([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "registrations/{registrationId}/survey")] HttpRequestData req, string registrationId)
    {
        var request = await JsonSerializer.DeserializeAsync<SurveyRequest>(req.Body, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (request is null) return await Support.TextAsync(req, "Missing survey data.", HttpStatusCode.BadRequest);

        var now = DateTimeOffset.UtcNow;
        var surveys = Support.Table("TABLE_SURVEY_RESPONSES", "SurveyResponses");
        await surveys.CreateIfNotExistsAsync();
        await surveys.UpsertEntityAsync(new TableEntity(Support.RegistrationPartitionKey(registrationId), "SURVEY")
        {
            ["email"] = string.IsNullOrWhiteSpace(request.Email) ? "" : Support.NormalizeEmail(request.Email),
            ["preferredStyle"] = request.PreferredStyle ?? "",
            ["participantsCount"] = request.ParticipantsCount,
            ["usagePurpose"] = request.UsagePurpose ?? "",
            ["notes"] = request.Notes ?? "",
            ["submittedUtc"] = now
        });

        var regs = Support.Table("TABLE_SESSION_REGISTRATIONS", "SessionRegistrations");
        var found = new List<TableEntity>();
        await foreach (var e in regs.QueryAsync<TableEntity>(x => x.RowKey == Support.RegistrationRowKey(registrationId))) found.Add(e);
        if (found.Count > 0)
        {
            var reg = found[0];
            reg["surveyStatus"] = "Submitted";
            reg["updatedUtc"] = now;
            await regs.UpdateEntityAsync(reg, reg.ETag, TableUpdateMode.Replace);
        }

        return await Support.JsonAsync(req, new { registrationId, status = "Submitted" });
    }
}
