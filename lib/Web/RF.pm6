use v6;
use Crust::Request;
use Path::Router;

subset Post of Crust::Request is export where { $_.method eq 'POST' };
subset Get of Crust::Request is export where { $_.method eq 'GET' };

class X::BadRequest is Exception is export { }
class X::NotFound is Exception is export { }

class Web::RF::Redirect is export {
    has $.code;
    has $.url;

    multi method new($code, $url) { self.new(:$code, :$url) }

    method handle() { [ $.code, [ 'Location' => $.url ], []] }

    multi method go(:$code!, :$url!) { self.new(:$code, :$url).handle(); }
    multi method go($code, $url) { self.go(:$code, :$url) }
}

class Web::RF::Controller is export {
    has $.router is rw;
    method url-for($controller) {
        return $.router.url-for($controller);
    }

    multi method handle {
        die X::BadRequest.new;
    }
}

class Web::RF::Router is export {
    has $.router;
    has $.parent is rw;

    submethod BUILD {
        $!router = Path::Router.new;
        self.routes();
    }

    method match($path) {
        $!router.match($path);
    }
    method url-for($controller) {
        if $.parent {
            return $.parent.url-for($controller);
        }

        for $!router.routes {
            return $_.path if $_.target.WHAT eqv $controller.WHAT;
        }
    }

    multi method route(Str $path, Web::RF::Controller $target) {
        my $t = $target.defined ?? $target !! $target.new;
        $t.router = self;
        $!router.add-route($path, target => $t);
    }
    multi method route(Str $path, Web::RF::Router:D $target) {
        $target.parent = self;
        $!router.include-router($path => $target.router);
    }
    multi method route(Str $path, Web::RF::Router:U $target) {
        self.route($path, $target.new);
    }

    method routes {
        !!!;
    }

    method before(:$request) { }
    method error(:$request, :$exception) { }
}

class Web::RF is export {
    has $.root;

    method handle(%env) {
        my $request = Crust::Request.new(%env);
        
        my $uri = $request.request-uri.subst(/\?.+$/, '');

        my $resp = $.root.before(:$request);
        unless $resp {
            my $page = $.root.match($uri);
            if $page {
                 $resp = $page.target.handle(:$request, :mapping($page.mapping));
            }
            else {
                die X::NotFound.new;
            }
        }
        return $resp;

        CATCH {
            when X::BadRequest {
                return $.root.error(:$request, :exception($_)) || [400, [], []];
            }
            when X::NotFound {
                return $.root.error(:$request, :exception($_)) || [404, [], []];
            }
            default {
                return $.root.error(:$request, :exception($_)) || $_.rethrow;
            }
        }
    }
}
