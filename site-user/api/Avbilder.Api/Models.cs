using System.Text.Json.Serialization;

namespace Avbilder.Api;

public sealed record RegistrationRequest(
    string SessionId,
    string AttendeeName,
    string Email,
    string? Phone,
    string? PreferredDate,
    string? PreferredStyle,
    int ParticipantsCount,
    string? UsagePurpose,
    string? Notes);

public sealed record SurveyRequest(
    string? Email,
    string? PreferredStyle,
    int ParticipantsCount,
    string? UsagePurpose,
    string? Notes);

public sealed record PreviewAccessResponse(string RegistrationId, IEnumerable<string> Urls);

public sealed class ClientPrincipalEnvelope
{
    [JsonPropertyName("clientPrincipal")]
    public ClientPrincipal? ClientPrincipal { get; set; }
}

public sealed class ClientPrincipal
{
    [JsonPropertyName("identityProvider")]
    public string? IdentityProvider { get; set; }
    [JsonPropertyName("userId")]
    public string? UserId { get; set; }
    [JsonPropertyName("userDetails")]
    public string? UserDetails { get; set; }
    [JsonPropertyName("userRoles")]
    public string[] UserRoles { get; set; } = [];
    [JsonPropertyName("claims")]
    public ClientPrincipalClaim[] Claims { get; set; } = [];
}

public sealed class ClientPrincipalClaim
{
    [JsonPropertyName("typ")]
    public string? Type { get; set; }

    [JsonPropertyName("val")]
    public string? Value { get; set; }
}
