# Versioning Guidelines (Internal)

We follow Semantic Versioning: MAJOR.MINOR.PATCH

Patch (x.y.Z): bugfixes only  
Minor (x.Y.z): new features, backwards compatible  
Major (X.y.z): breaking changes

Release process:
1. Update version in code
2. Tag the commit with "vX.Y.Z"
3. Build Linux and Windows binaries
4. Upload to GitHub Releases with matching tag
