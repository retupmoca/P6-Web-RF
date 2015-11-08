use v6;
use Crust::Request;
use Path::Router;

class Web::RF::Request is Crust::Request {
    method user-id {
        $.session.get('user-id');
    }
    method set-user-id($new?) {
        if $new {
            $.session.set('user-id', $new);
            $.session.change-id = True;
        }
        else {
            $.session.remove('user-id');
        }
    }
}

subset Post of Web::RF::Request is export where { $_.method eq 'POST' };
subset Get of Web::RF::Request is export where { $_.method eq 'GET' };
subset Authed of Web::RF::Request is export where { so $_.user-id }; 
subset Anon of Web::RF::Request is export where { !($_.user-id) }; 

class X::BadRequest is Exception is export { }
class X::NotFound is Exception is export { }
class X::PermissionDenied is Exception is export { }

class Web::RF::Redirect is export {
    has Int $.code where { $_ ~~ any(301, 302, 303, 307, 308) };
    has Str $.url where { $_.chars > 0 };

    multi method new($code, $url) { self.new(:$code, :$url) }

    method handle() { [ $.code, [ 'Location' => $.url ], []] }

    multi method go(:$code!, :$url!) { self.new(:$code, :$url).handle(); }
    multi method go($code, $url) { self.go(:$code, :$url) }
}

class Web::RF::Router { ... };

class Web::RF::Controller is export {
    has Web::RF::Router $.router is rw;
    method url-for(Web::RF::Controller $controller) {
        return $.router.url-for($controller);
    }

    multi method handle {
        die X::BadRequest.new;
    }
}
class Web::RF::Controller::Authed is Web::RF::Controller is export {
    # we list these for each method so this will always be the most specific
    # method in the list.
    multi method handle(Get :$request where Anon) {
        die X::PermissionDenied.new;
    }
    multi method handle(Post :$request where Anon) {
        die X::PermissionDenied.new;
    }
}

class Web::RF::Router is export {
    has Path::Router    $.router;
    has Web::RF::Router $.parent is rw;

    submethod BUILD {
        $!router = Path::Router.new;
        self.routes();
    }

    method match(Str $path) {
        $!router.match($path);
    }
    method url-for(Web::RF::Controller $controller) {
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
    has Web::RF::Router $.root;

    method handle(%env) {
        my $request = Web::RF::Request.new(%env);
        
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
            when X::PermissionDenied {
                return $.root.error(:$request, :exception($_)) || [403, [], []];
            }
            default {
                return $.root.error(:$request, :exception($_)) || $_.rethrow;
            }
        }
    }
}
