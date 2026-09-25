# Official download sources. HTTPS only.
# Hosts: exact host match (no subdomains), any path. Only hosts a download URL of the kit really needs
# (Microsoft uses aka.ms redirects).
# UrlPrefixes: a whole host is too broad (github.com hosts everyone's files), so these allow exactly one
# release folder of one project. The URL is normalized first ('..' segments resolved) and must start with
# the prefix; the signature check after the download stays the real guard.
@{
    Hosts = @(
        'aka.ms'
        'download.microsoft.com'
        'download.visualstudio.microsoft.com'
    )
    UrlPrefixes = @(
        'https://github.com/nefarius/ViGEmBus/releases/download/'
    )
}
