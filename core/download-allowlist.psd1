# Official download hosts. Exact host match only (no subdomains), HTTPS only.
# GitHub release assets redirect to *.githubusercontent.com, Microsoft uses aka.ms redirects.
@{
    Hosts = @(
        'github.com'
        'objects.githubusercontent.com'
        'release-assets.githubusercontent.com'
        'aka.ms'
        'download.microsoft.com'
        'download.visualstudio.microsoft.com'
    )
}
