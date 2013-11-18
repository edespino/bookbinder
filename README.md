# Bookbinder

Bookbinder is a gem that binds together a unified documentation web-app from disparate source material, stored as repositories of markdown on GitHub. It runs [middleman](http://middlemanapp.com/) to produce a (CF-pushable) Sinatra app.

## About

Bookbinder is meant to be used from within a "book" project. The book project provides a configuration of which documentation repositories to pull in; the bookbinder gem provides a set of scripts to aggregate those repositories and publish them to various locations. It also provides scripts for running a CI system that can detect when a documentation repository has been updated with new content, and then verify that the composed book is free of any dead links.

## Setting Up a Book Project

A book project needs a few things to allow bookbinder to run. Here's the minimal directory structure you need in a book project:

```
.
├── Gemfile
├── Gemfile.lock
├── .gitignore
├── .ruby-version
├── config.yml
└── master_middleman
    ├── config.rb
    └── source
        └── index.html.md
```

`Gemfile` needs to point to this bookbinder gem, and probably no other gems. `Gemfile.lock` can be created by bundler automatically (see below).

`config.yml` is a YAML file that represents a hash. The following keys are used:

- **repos**: an array of hashes which specifies which documentation repositories to pull in. Each hash needs to specify
    - **github_repo**: the path on github to this repository, i.e. 'organization/repository'. The organization is ignored when finding repositories locally. The repository must be public (unless finding repositories locally).
    - **directory**: (optional) a "pretty" directory path under the main root that the webapp will use for this sub-repo.
    - **sha**: (optional) the sha of the repo to use when downloading it from github. Ignored when finding repositories locally.
- **github**: Github credentials - used for Github API calls. We recommend using a non-person "role" account for this.
    - **username**: github username
    - **password**: github password
- **pdf**: (optional) Bookbinder can generate a PDF from one output (.html) file. To format it properly, you need to include print-specific stylesheets.
    - **page**: path of webpage to turn into a PDF (remember to use the "pretty" path if using the 'directory' key in the repo)
    - **filename**: name of the outputted PDF
- **aws**: For CI and deployment scripts. These allow bookbinder's CI scripts to push/pull green builds to/from S3
    - **access_key**: your AWS access key
    - **secret_key**: your AWS secret key
    - **green_builds_bucket**: This is where we store builds (on S3) that go green on Jenkins, and are ready to be pushed to production.
- **cloud_foundry**: For deployment scripts. As with github, we advise to use a non-person "role" account here. For staging and production servers, we assume you have already created a **app_name** application within the specified spaces (pushes will fail if the app is not yet in place).
    - **username**: CF username
    - **password**: CF password
    - **api_endpoint**: e.g. https://api.run.pivotal.io
    - **organization**: e.g. pivotal
    - **app_name**: e.g. docs
    - **staging_space**: e.g. docs-pivotalone-staging
    - **production_space**: e.g. docs-pivotalone-prod

`.gitignore` should contain the following entries, which are directories generated by bookbinder:

    output
    final_app

`master_middleman` is a directory which forms the basis of your site. [Middleman](http://middlemanapp.com/) configuration and top-level assets, javascripts, and stylesheets are all placed in here. You can also have ERB layout files. Each time a publish operation is run, this directory is copied into output/. Then each doc-repo is copied (as a directory) into the source folder, before middleman is run to generate the final app.

`.ruby-version` is used by [rbenv](https://github.com/sstephenson/rbenv) to find the right ruby. We haven't tested bookinbder with RVM so we don't know if it will work, so we recommend rbenv unless you are feeling experimental. WARNING: If you install rbenv, you MUST uninstall RVM first (http://robots.thoughtbot.com/post/47273164981/using-rbenv-to-manage-rubies-and-gems).

## Bootstrapping with Bundler

Bookbinder uses bundler and we recommend installing [rbenv](https://github.com/sstephenson/rbenv).

Once rbenv is set up and the correct ruby version is set up (2.0.0-p195), run (in your book project)

    gem install bundler
    bundle

And you should be good to go!


Bookbinder's entry point is the `bookbinder` executable. The following commands are available:

### `publish`

Bookbinder's most important command is `publish`. It takes one argument on the command line:

        bookbinder publish local

will find documentation repositories in directories that are siblings to your current directory, while

        bookbinder publish github

will find doc repos by downloading the latest version from github.

The publish command creates 2 output directories, one named `output/` and one named `final_app/`. These are placed in the current directory and are cleared each time you run bookbinder.

`final_app/` contains bookbinder's ultimate output: a Sinatra web-app that can be pushed to cloud foundry or run locally.

`output/` contains intermediary state, including the final prepared directory that the `publish` script ran middleman against, in `output/master_middleman`.

## Running the App Locally

    cd final_app
    bundle
    ruby app.rb

You should only need to run the `bundle` the first time around.

## CI

### CI for Books

Part of what makes bookbinder awesome is that it can drive a continuous integration process for your book, using Jenkins.

The goal of this CI is to run a full publish operation every time either of the following changes:

- Your book's configuration, i.e. any change to your main book git repo.
- Any of the document sub-repositories that the configuration depends on (listed in config.yml).

The book CI should have 2 Jenkins builds to accomplish this. Both should link to the same repository (the book repository). Both use scripts from the bookbinder gem.

The **Change Monitor Build** build is simply a cron-like build that runs every minute, and detects if any of the document repositories have changed; if they have, it triggers the publish build to run. The **Publish Build**, when triggered, runs a full publish operation. If the publish build goes green (i.e. there are no broken links), it will deploy to staging and also generate a tarball of the green build, which is stored on S3 with a build number in the filename.

### CI Technical Details

CIBorg can be used to stand up an AWS box running jenkins. The CloudFoundry Go CLI should be installed on the Jenkins box to ~jenkins/bin/go-cf (bookbinder's scripts expect it to be in the ~/bin of the current user). Here's how to copy down the prebuilt binary.

    curl http://go-cli.s3.amazonaws.com/go-cf-linux-amd64.tgz > go-cf-linux-amd64.tgz
    tar xzf go-cf-linux-amd64.tgz

The following Jenkins plugins are necessary:

- Rbenv (configured to use ruby version 2.0.0p195)
- Jenkins GIT

#### *Change Monitor Build*
This build executes this shell command

    bundle install
    bundle exec bookbinder doc_repos_updated

and builds the **Publish Build** project on success as a post-build action.

This build determines whether a full publish build should be triggered, based on some cached state that it stores in a file. This file, called cached_shas.yml, is kept in the job folder of the change monitor build (i.e. one level above the actual workspace), so that it persists between builds.

#### *Publish Build*
This build should executes this shell command:

    bundle install
    bundle exec bookbinder run_publish_ci

## Deploying

Bookbinder has the ability to deploy the finished product to either staging or production.

Deploying to staging is not normally something a human needs to do: the book's Jenkins CI script does this automatically every time a build passes.

To deploy to production, you need to have CloudFoundry Go CLI installed; assuming you have the go-cf command-line tool installed and on your PATH, the following command will deploy the build in your local 'final_app' directory to staging:

    bookbinder push_local_to_staging

Deploying to prod can be done from any machine with the book project checked out, but does not depend on the results from a local publish (or the contents of your `final_app` directory). Instead, it pulls the latest green build from S3, untars it locally, and then pushes it up to prod:

    bookbinder push_to_prod <build_number>

If the build_number argument is left out, the latest green build will be deployed to production.

## Generating a Sitemap for Google

Assuming your URL is docs.foo.com:

`grep \\.html output/wget.log | grep "\-\-" | sed s/^.*localhost:4534/http:\\/\\/docs.foo.com/ | uniq`


## Contributing to Bookbinder

### Running Tests

To run bookbinder's rspec suite, use bundler like this: `bundle exec rspec`.

### CI

Bookbinder has a [CI on Travis](https://travis-ci.org/pivotal-cf/docs-bookbinder) that runs all its unit tests.
