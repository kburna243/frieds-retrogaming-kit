# Official download hosts. Exact host match only (no subdomains), HTTPS only.
# Only hosts a download URL of the kit really needs (Microsoft uses aka.ms redirects). Add GitHub
# (github.com + its asset hosts) only together with the first package that downloads from there.
@{
    Hosts = @(
        'aka.ms'
        'download.microsoft.com'
        'download.visualstudio.microsoft.com'
    )
}
