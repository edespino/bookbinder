[![Code Climate](https://codeclimate.com/github/pivotal-cf/docs-bookbinder.png)](https://codeclimate.com/github/cloudfoundry-incubator/bookbinder) [![Build Status](https://travis-ci.org/cloudfoundry-incubator/bookbinder.png)](https://travis-ci.org/cloudfoundry-incubator/bookbinder)
# Bookbinder

Bookbinder is a gem that binds together a unified documentation web-app from disparate source material, stored as repositories of markdown or plain HTML on GitHub. It runs [middleman](http://middlemanapp.com/) to produce a (CF-pushable) Rackup app.

## About

Bookbinder is meant to be used from within a "book" project. 
The book project provides a configuration of which documentation repositories to pull in; the bookbinder gem provides a set of scripts to aggregate those repositories and publish them to various locations.
It also provides scripts for running a CI system that can detect when a documentation repository has been updated with new content, and then verify that the composed book is free of any dead links.

## Setting Up a Book Project

Note: Bookbinder requires Ruby version 2.0.0-p195 or higher.

### Setup Checklist
Please read this document to understand how to set up a new book project.  You can refer to this checklist for the steps that must completed manually when setting up your book:

#### Creating and configuring your book
- Create a git repo for the book and populate it with the required files (or use an existing book repo as a template).
- Add list of included doc sections to `config.yml`.
- (For private repositories) Create a Github [SSH key](https://help.github.com/articles/generating-ssh-keys/) for bookbinder from an account that has access to the documentation repositories.
- (For private repositories) ssh-add this key locally. Bookbinder will use whatever keys your system knows about by default.
- Publish and run the server locally to test your book.

#### Deploying your book
- Create AWS bucket for green builds and put info into `credentials.yml`
- Set up CF spaces for staging and production and put details into `credentials.yml`
- Deploy to production
- (optional) Register your sitemap with Google Webmaster Tools

### Book Repository
A book project needs a few things to allow Bookbinder to run. Here's the minimal directory structure you need in a book project:

```
.
├── Gemfile
├── Gemfile.lock
├── .gitignore
├── .ruby-version
├── (optional) <PDF index>.yml
├── (optional) redirects.rb
├── config.yml
└── master_middleman
    ├── config.rb
    ├── source
    |   ├── index.html.md
    |   ├── layouts
    |   |   └── layout.erb
    |   └── subnavs
    |   |   └── _default.erb
    |   └── (optional) archive_menus
    |	    └── _default.erb
    └── <Top level folder of "pretty" directory path>
        └── (optional) index(.html)(.md)(.erb)
```

`Gemfile` needs to point to this bookbinder gem, and probably no other gems.

`config.yml` is a YAML file that holds all the information bookbinder needs. The following keys are used:

```YAML
book_repo: org-name/repo-name
cred_repo: org-name/private-repo
layout_repo: org-name/master-middleman-repo		# non-optional for the generate_pdf command

sections:
  - repository:
      name: org-name/bird-repo
      ref: 165c28e967d58e6ff23a882689c953954a7b588d
    directory: birds
    subnav_template: cool-sidebar-partial		# optional
  - repository:
      name: org-name/reptile-repo
      ref: d07101dec08a698932ef0aa2fc36316d6f7c4851
    directory: reptiles
    
archive_menu:						# optional
  - v1.3.0.0
  - v1.2.0.0: archive-repo/your_pdf.yml

public_host: animals.example.com
pdf:
  header: path/to/header-file.html
template_variables:					# optional
  var_name: special-value
  other_var: 12

```

`.gitignore` should contain the following entries, which are directories generated by bookbinder:

    output
    final_app

`master_middleman` is a directory which forms the basis of your site. [Middleman](http://middlemanapp.com/) configuration and top-level assets, javascripts, and stylesheets should all be placed in here. You can also have ERB layout files. Each time a publish operation is run, this directory is copied to `output/master_middleman`. Then each section repo is copied (as a directory) into `output/master_middleman/source/`, before middleman is run to generate the final app. If you specify a `layout_repo:` in `config.yml`, that directory will be copied instead of `master_middleman`.

`.ruby-version` is used by [rbenv](https://github.com/sstephenson/rbenv) or [rvm](https://rvm.io/) to find the right ruby.  WARNING: If you install rbenv, you MUST uninstall RVM first: [see details here](http://robots.thoughtbot.com/post/47273164981/using-rbenv-to-manage-rubies-and-gems).

### Layout Repository

If layout repository is set to the full name of a Github repository (eg `cloudfoundry/bosh`), it will be downloaded for use as your book's `master_middleman` directory.

### Credentials Repository

The credentials repository should be a private repository, referenced in your config.yml as `cred_repo`. It contains `credentials.yml`, which must include your deployment credentials:

```YAML
aws:
  access_key: AKIAIOSFODNN7EXAMPLE
  secret_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYzEXAMPLEKEY
  green_builds_bucket: s3_bucket_name
cloud_foundry:
  username: sam
  password: pel
  api_endpoint: https://api.run.pivotal.io
  organization: documentation-team
  app_name: docs
  staging_space: docs-staging
  production_space: docs-production
  staging_host:
    cfapps.io: 
      - staging-route-subdomain
      - another-staging-route-subdomain
  production_host:
    cfapps.io: 
      - production-route-subdomain
```

## Middleman Templating Helpers

Bookbinder comes with a Middleman configuration that provides a handful of helpful functions, and should work for most Book Projects. To use a custom Middleman configuration instead, place a `config.rb` file in the `master_middleman` directory of the Book Project (this will overwrite Bookbinder's `config.rb`).

Bookbinder provides several helper functions that can be called from within a .erb file in a doc repo, such as a layout file.

### Quick Links
`<%= quick_links %>` produces a table of contents based on in-page anchors.

### Breadcrumbs
`<%= breadcrumbs %>` generates a series of breadcrumbs as a UL HTML tag. The breadcrumbs go up to the site's top-level, based on the title of each page. The bottom-most entry in the list of breadcrumbs represents the current page; the rest of the breadcrumbs show the hiearchy of directories that the page lives in. Each breadcrumb above the current page is generated by looking at the [frontmatter](http://middlemanapp.com/frontmatter/) title of the index template of that directory. If you'd like to use breadcrumb text that is different than the title, an optional 'breadcrumb' attribute can be used in the frontmatter section to override the title.

### Subnavs
`<%= yield_for_subnav %>` inserts the appropriate template in /subnavs, based on each constituent repositories' `subnav_template:` parameter in config.yml. The default template (`\_default.erb`) uses the label `default` and is applied to all sections unless another template is specified with subnav\_template. Template labels are the name of the template file with extensions removed. ("sample" for a template named "sample.erb")

### Last Modified
`<%= modified_date [format]%>` will evaluate to the time at which the current page was last modified. The format string is optional: if specified (e.g. "%Y/%m/%d"), the date will be printed accordingly. If not specified, the date will look like '2013-11-13 20:00:18 UTC'.

### Code Snippets
`<%= yield_for_code_snippet from: 'my-org/code-repo', at: 'myCodeSnippetA' %>` inserts code snippets extracted from code repositories.

To delimit where a code snippet begins and ends, you must use the format of `code_snippet MARKER_OF_YOUR_CHOOSING start OPTIONAL_LANGUAGE`, followed by the code, and then finished with `code_snippet MARKER_OF_YOUR_CHOOSING end`:
If the `OPTIONAL_LANGUAGE` is omitted, your snippet will still be formatted as code but will not have any syntax highlighting.

```clojure

; code_snippet myCodeSnippetA start clojure
	(def fib-seq
   	  (lazy-cat [0 1] (map + (rest fib-seq) fib-seq)))
	user> (take 20 fib-seq)
	(0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181)
; code_snippet myCodeSnippetA end

```

### Archive Menu

Bookbinder allows you to specify a dropdown menu template for use in the navbar. This can contain links to PDFs or other archived versions of documentation. To specify a dropdown menu, add the `archive_menu` key in config.yml as follows:

```
  archive_menu:
    - v1.3.0.0
    - v1.2.0.0: my-pdf-repo/v1.2.0.0.pdf
```

The first key (e.g. v1.3.0.0) is available for use as a title in your navbar. You can configure the structure of the dropdown menu by creating a template in `master_middleman/source/archive_menus/_default.erb`.

Finally, to insert the archive menu, use the `<%= yield_for_archive_menu %>` tag in the appropriate part of the navbar in your layout.erb. 

### Including Assets 
Bookbinder also includes helper code to correctly find image, stylesheet, and javascript assets. When using `<% image_tag ...`, `<% stylesheet_link_tag ...`, or `<% javascript_include_tag ...` to include assets, Bookbinder will search the entire directory structure starting at the top-level until it finds an asset with the provided name. For example, when resolving `<% image_tag 'great_dane.png' %>` called from the page `dogs/big_dogs/index.html.md.erb`, Middleman will first look in `images/great_dane.png.` If that file does not exist, it will try `dogs/images/great_dane.png`, then `dogs/big_dogs/images/great_dane.png`.

## Bootstrapping with Bundler

Once rbenv or rvm is set up and the correct ruby version is set up (2.0.0-p195), run (in your book project)

    gem install bundler
    bundle

And you should be good to go!

Bookbinder's entry point is the `bookbinder` executable. It should be invoked from the book directory. The following commands are available:

### `publish` command

Bookbinder's most important command is `publish`. It takes one argument on the command line:

        bundle exec bookbinder publish local

will find documentation repositories in directories that are siblings to your current directory, while

        bundle exec bookbinder publish github

will find doc repos by downloading the latest version from github.

The publish command creates 2 output directories, one named `output/` and one named `final_app/`. These are placed in the current directory and are cleared each time you run bookbinder.

`final_app/` contains bookbinder's ultimate output: a Rack web-app that can be pushed to cloud foundry or run locally.

The Rack web-app will respect redirect rules specified in `redirects.rb`, so long as they conform to the `rack/rewrite` [syntax](https://github.com/jtrupiano/rack-rewrite), eg:

```ruby
rewrite   '/wiki/John_Trupiano',  '/john'
r301      '/wiki/Yair_Flicker',   '/yair'
r302      '/wiki/Greg_Jastrab',   '/greg'
r301      %r{/wiki/(\w+)_\w+},    '/$1'
```


`output/` contains intermediary state, including the final prepared directory that the `publish` script ran middleman against, in `output/master_middleman`.

As of version 0.2.0, the `publish` command no longer generates PDFs.

### `generate_pdf` command

`$ bookbinder generate_pdf` will generate a PDF against the currently available `final_app` directory. You must run `publish [local | github]` before running `generate_pdf`.

You can specify which pages to include in a PDF using `$ bookbinder generate_pdf my-pdf.yml`. `my-pdf.yml` contains the configuration for the pdf. It must be formatted as YAML and **requires the keys** `header` and `pages`.

`my-pdf.yml` example:

```yml
---
copyright_notice: 'Copyright Pivotal Software Inc, 2042-2043'
header: some-header.html
pages:
    - my-book/intro.html
    - my-book/dramatic-peak.html
    - my-book/denouement.html
```

Each path provided under `pages` must match the `directory` of its `repository` in `config.yml`.
The header is pulled in from the `layout_repo`, so the file `some-header.html` is expected to exist at the top level in the repo `my-username/my-layout`. The contents of `some-header.html` will be added as a header to each page within the generated pdf.

Here's an example of `some-header.html`:
```
<!DOCTYPE html>
<html>
  <body>
    <div class='pdf_header' style="background-color:#ffffff; padding:12px 0px 12px 10px">
    	<img src='images/logo-big.png' style="height:20px">
    </div>
  </body>
</html>
```

So for the above pages to publish to pdf, your `config.yml` must contain

```yml
---
layout_repo: my-username/my-layout
sections:
- repository:
    name: my-username/my-book
    directory: my-book
```

and in turn, `my-username/my-layout` must contain `some-header.html`; and `my-username/my-book` must contain the pages `intro.html`, `dramatic-peak.html`, and `denouement.html`.

An optional copyright notice may be provided as shown in the example.

The output pdf file will have the same name as the YAML file used to generate it. In this example, it will be `my-pdf.pdf` since its configuration was specfied in `my-pdf.yml`.

### `update_local_doc_repos` command

As a convenience, Bookbinder provides a command to update all your local doc repos, performing a git pull on each one:

        bundle exec bookbinder update_local_doc_repos

### `tag` command

The `bookbinder tag` command commits Git tags to checkpoint a book and its constituent document repositories. This allows the tagged version of the documentation to be re-generated at a later time.

    bundle exec bookbinder tag book-formerly-known-as-v1.0.1

## Running the App Locally

    cd final_app
    bundle
    ruby app.rb

This will start a Rackup server to serve your documentation website locally at [http://localhost:4567/](http://localhost:4567/). While making edits in documentation repos, we recommend leaving this running in a dedicated shell window.  It can be terminated by hitting `ctrl-c`.

You should only need to run the `bundle` the first time around.


## Continuous Integration

### CI for Books

The currently recommended tool for CI with Bookbinder is GoCD.

#### CI Runner
You will want a build that executes this shell command:

    bundle install
    bundle exec bookbinder run_publish_ci
    
This will publish a book and push it to staging.

## <a name="deploying"></a>Deploying

Bookbinder has the ability to deploy the finished product to either staging or production. The deployment scripts use the gem's pre-packaged CloudFoundry Go CLI binary (separate versions for darwin-amd64 and linux-amd64 are included); any pre-installed version of the CLI on your system will **not** be used.

### Setting up CF Apps

Each book should have a dedicated CF space and host for its staging and production servers.
The Cloud Foundry organization and spaces must be created manually and specified as values for "organization", "staging_space" and "production_space" in `config.yml`.
Upon the first and second deploy, bookbinder will create two apps in the space to which it is deploying. The apps will be named `"app_name"-blue` and `"app_name"-green`.  These will be used for a [blue-green deployment](http://martinfowler.com/bliki/BlueGreenDeployment.html) scheme.  Upon successful deploy, the subdomain of `cfapps.io` specified by "staging_host" or "production_host" will point to the most recently deployed of these two apps.


### Deploy to Staging
Deploying to staging is not normally something a human needs to do: the book's CI script does this automatically every time a build passes.

The following command will deploy the build in your local 'final_app' directory to staging:

    bundle exec bookbinder push_local_to_staging

### Deploy to Production
Deploying to prod is always done manually. It can be done from any machine with the book project checked out, but does not depend on the results from a local publish (or the contents of your `final_app` directory). Instead, it pulls the latest green build from S3, untars it locally, and then pushes it up to prod:

    bundle exec bookbinder push_to_prod <build_number>

If the build_number argument is left out, the latest green build will be deployed to production.

## Generating a Sitemap for Google Search Indexing

The sitemap file `/sitemap.xml` is automatically regenerated when publishing. When setting up a new docs website, make sure to add this sitemap's url in Google Webmaster Tools (for better reindexing?).

## Contributing to Bookbinder

### Running Tests

To run bookbinder's rspec suite, use bundler like this: `bundle exec rspec`.
