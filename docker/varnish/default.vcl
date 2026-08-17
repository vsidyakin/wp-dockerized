vcl 4.1;

backend default {
    .host = "wordpress";
    .port = "80";
    .connect_timeout = 5s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 30s;

    .probe = {
        .url = "/healthz.php";
        .timeout = 3s;
        .interval = 10s;
        .window = 5;
        .threshold = 3;
    }
}

acl purge {
    "localhost";
    "127.0.0.1";
    "wordpress";
}

sub vcl_recv {
    if (req.restarts == 0) {
        if (req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    if (req.url == "/healthz") {
        set req.url = "/healthz.php";
        return (pass);
    }

    if (req.method == "PURGE") {
        if (client.ip !~ purge) {
            return (synth(403, "PURGE is restricted to the application network"));
        }
        return (purge);
    }

    if (req.method == "BAN") {
        if (client.ip !~ purge) {
            return (synth(403, "BAN is restricted to the application network"));
        }
        ban("obj.http.X-Cache-Host == " + req.http.host + " && obj.http.X-Cache-Url ~ " + req.url);
        return (synth(200, "Ban added"));
    }

    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    if (req.http.Authorization
        || req.url ~ "^/wp-(admin|login\.php|cron\.php|comments-post\.php|activate\.php)"
        || req.url ~ "^/wp-json/"
        || req.url ~ "^/xmlrpc\.php"
        || req.url ~ "[?&](preview|s|add-to-cart|wc-api)="
        || req.http.Cookie ~ "wordpress_(logged_in|sec)|wp-postpass|comment_author|woocommerce_|wp_woocommerce_session") {
        return (pass);
    }

    return (hash);
}

sub vcl_backend_response {
    set beresp.grace = 1h;
    set beresp.keep = 5m;
    set beresp.http.X-Cache-Host = bereq.http.host;
    set beresp.http.X-Cache-Url = bereq.url;

    if (bereq.url == "/healthz.php"
        || beresp.status >= 500
        || beresp.http.Set-Cookie
        || beresp.http.Cache-Control ~ "(?i)(private|no-cache|no-store)"
        || beresp.ttl <= 0s) {
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
        return (deliver);
    }

    if (beresp.ttl > 10m) {
        set beresp.ttl = 10m;
    }

    return (deliver);
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    unset resp.http.X-Cache-Host;
    unset resp.http.X-Cache-Url;
    unset resp.http.Via;
    unset resp.http.X-Varnish;
}
