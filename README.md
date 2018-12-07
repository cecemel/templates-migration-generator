# Migration generator
Basic generator of migrations for the templates.

Checks for changes in https://github.com/lblod/editor-templates (locally)
Expects .ttls as input. (skips non TTL)
Flushes what needs to be changed.
Creates migrations for changes.
Moves the templates to public graph.

## Caveats
Many.. so the #1 rule would be to check the generated output!
<dl>
  <dt>Doesn't take into account deleted files</dt>
  <dt>Naivly and silently assumes 1 template per TTL file.</dt>
  <dt>Only assumes ext:Template in these files</dt>
</dl>

## Expected input
<dl>
<dt>/path/to/templates-repo</dt>
<dd>olderCommit</dd>
<dd>newerCommit</dd>
</dl>

## Running the generator
The script can be executed in a Docker container through the following command:
```bash
docker run -it --rm -v "$PWD":/app -v /path/to/git/repo:/repo -w /app ruby:2.5 ./run.sh HEAD^ HEAD
```
Last argument: last until recent commit


## Developing the script
Start a Docker container:
```bash
docker run -it --name migration-generator -v "$PWD":/app  -v /path/to/git/repo:/repo-w /app ruby:2.5 /bin/bash
```

Execute the following commands in the Docker container:
```bash
bundle install
ruby app.rb
```
