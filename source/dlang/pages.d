module dlang.pages;

import dlang.site;

import std.string;
debug import std.stdio;

import vibe.core.log;
import vibe.http.server;
import vibe.http.client;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.stream.operations;

import ddoc.macros;
import ddoc.standalone;

shared static this() {
	import std.datetime : msecs;
	// Running this is a timer avoids the cache
	// being parsed in the command line.
	// E.g, we don't want './dlang.org --help' to fill the cache.
	setTimer(1.msecs, () => initialize());
}

private:
void initialize() {
	auto router = new URLRouter;
	debug router.any("*", &debugHandler);
	router.get("*", &cacheHandler);
	router.get("/favicon.ico", serveStaticFile("./favicon.ico"));
	
	logInfo("Initializing website");
	initializeWebsite(s_cache, router);
	logInfo("Cache contains %d elements", s_cache.length);

	//logInfo("Initializing druntime");
	//initializeDruntime(s_cache, router);

	/* HTTP Settings & routes creation */
	auto settings = new HTTPServerSettings;
	settings.port = 8000;
	settings.bindAddresses = [ "0.0.0.0" ];

	router.get("/css/cssmenu.css", &cssHandler);
	router.get("/css/*", serveStaticFiles("./"));
	router.get("/js/*", serveStaticFiles("./"));
	router.get("/images/*", serveStaticFiles("./"));
	router.get("/prettify/*", serveStaticFiles("./"));

	registerPhobos(router);
	
	listenHTTP(settings, router);
}

void initializeWebsite(ref shared(string[string]) cache, URLRouter router) {
	// SiteMacros and Latest are in dlang.site (enums).
	auto ctx = parseMacrosFile(SiteMacros);
	ctx["LATEST"] = Latest;

	foreach (idx, p; StaticPagesInput) {
		logInfo("[DDOC] Processing file %s", p);
		cache[StaticPages[idx]] = parseFile(p, ctx);
	}

	logInfo("[DDOC] Processing file css/cssmenu.css");
	cache["cssmenu.css"] = parseFile("css/cssmenu.css.dd", null);

	foreach (page; [ `/appendices.html`, `/articles.html`,
			 `/dcompiler.html`, `/debugger.html`,
			 `/howtos.html`, `/language-reference.html` ])
		router.get(page, serveStaticFiles("./"));

	router.get("/", staticRedirect("/index.html"));
	logInfo("[INIT] Static website initialized");
}

void registerPhobos(URLRouter router) {
	enum SupportedVersions = ["2.065.0", "2.066.1", /* "2.067.0" */];

	foreach (idx, version_; SupportedVersions) {
		auto settings = new HTTPFileServerSettings;
		auto from = "/"~version_~"/phobos/*";
		auto to = "./public/"~version_~"/phobos/";
		settings.serverPathPrefix = from;
		router.get(from, serveStaticFiles(to, settings));
		logInfo("[FILE] Registered %s => %s", from, to);
		if (idx == (SupportedVersions.length - 1)) {
			router.get("/phobos/*", staticRedirect(from[0..$-1]));
			logInfo("[REDIR] Registered /phobos/ => %s", from[0..$-1]);
		}
	}
	//router.get("/phobos/", staticRedirect(LatestLink));
	//logInfo("Registered /phobos/ => %s", to);
}

void cssHandler(HTTPServerRequest req, HTTPServerResponse res) {
	auto p = "cssmenu.css" in s_cache;
	assert(p !is null, "cssmenu.css cannot be null !");
	res.writeBody(*p, "text/css");
}

void cacheHandler(HTTPServerRequest req, HTTPServerResponse res) {
	if (auto data = req.path in s_cache) {
		res.writeBody(*data, "text/html");
	}
}

void debugHandler(HTTPServerRequest req, HTTPServerResponse res) {
	import std.datetime;
	logInfo("[%s][%s] %s %s", req.clientAddress.toAddressString(),
		Clock.currTime(), req.method, req.path);
}
