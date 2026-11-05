/* io-nanosvg.c: an SVG loader module for gdk-pixbuf, drawn by NanoSVG (no librsvg, no Rust).
 *
 * Panels and apps load their SVG icons through gdk-pixbuf: sfwbar's gauges, the scalable icons of
 * hicolor, wallpapers for swaybg. NanoSVG draws paths, basic shapes, gradients, transforms and
 * opacity; it skips text, filters, masks, <style> sheets and XInclude (GTK's symbolic recolouring
 * of SVG icons needs those: the icon theme of the spin has PNGs for them).
 *
 * SPDX-License-Identifier: MIT
 */
#define GDK_PIXBUF_ENABLE_BACKEND
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gmodule.h>
#include <math.h>
#include <string.h>

#define NANOSVG_IMPLEMENTATION
#define NANOSVG_ALL_COLOR_KEYWORDS
#include "nanosvg.h"
#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvgrast.h"

/* the largest image it makes (a wallpaper of 8K), against SVGs with absurd sizes */
#define MAX_SIDE 8192

typedef struct {
	GdkPixbufModuleSizeFunc size_func;
	GdkPixbufModulePreparedFunc prepared_func;
	GdkPixbufModuleUpdatedFunc updated_func;
	gpointer user_data;
	GByteArray *data;
} SvgContext;

static gpointer begin_load(GdkPixbufModuleSizeFunc size_func, GdkPixbufModulePreparedFunc prepared_func,
			   GdkPixbufModuleUpdatedFunc updated_func, gpointer user_data, GError **error)
{
	(void)error;
	SvgContext *ctx = g_new0(SvgContext, 1);
	ctx->size_func = size_func;
	ctx->prepared_func = prepared_func;
	ctx->updated_func = updated_func;
	ctx->user_data = user_data;
	ctx->data = g_byte_array_new();
	return ctx;
}

static gboolean load_increment(gpointer data, const guchar *buf, guint size, GError **error)
{
	(void)error;
	SvgContext *ctx = data;
	g_byte_array_append(ctx->data, buf, size);
	return TRUE;
}

static int clamp_side(int v)
{
	return v < 1 ? 1 : v > MAX_SIDE ? MAX_SIDE : v;
}

static gboolean stop_load(gpointer data, GError **error)
{
	SvgContext *ctx = data;
	NSVGimage *image = NULL;
	NSVGrasterizer *rast = NULL;
	GdkPixbuf *pixbuf = NULL;
	gboolean ok = FALSE;

	g_byte_array_append(ctx->data, (const guint8 *)"", 1); /* nsvgParse wants a C string */
	image = nsvgParse((char *)ctx->data->data, "px", 96.0f);
	if (!image || !(image->width > 0.0f) || !(image->height > 0.0f)) {
		g_set_error_literal(error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_CORRUPT_IMAGE,
				    "Could not read the SVG image (or it has no size)");
		goto out;
	}
	int width = clamp_side((int)ceilf(image->width)), height = clamp_side((int)ceilf(image->height));
	int w = width, h = height;
	if (ctx->size_func) {
		ctx->size_func(&w, &h, ctx->user_data);
		if (w == 0 || h == 0) { /* the caller only wanted the size */
			ok = TRUE;
			goto out;
		}
		if (w < 0 || h < 0) {
			w = width;
			h = height;
		}
	}
	w = clamp_side(w);
	h = clamp_side(h);
	pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, w, h);
	rast = nsvgCreateRasterizer();
	if (!pixbuf || !rast) {
		g_set_error_literal(error, GDK_PIXBUF_ERROR, GDK_PIXBUF_ERROR_INSUFFICIENT_MEMORY,
				    "Not enough memory to draw the SVG image");
		goto out;
	}
	/* the image fills the size it was asked for, centred if the aspect ratio differs */
	float sx = (float)w / image->width, sy = (float)h / image->height, scale = sx < sy ? sx : sy;
	float tx = ((float)w - image->width * scale) / 2.0f, ty = ((float)h - image->height * scale) / 2.0f;
	guchar *pixels = gdk_pixbuf_get_pixels(pixbuf);
	int stride = gdk_pixbuf_get_rowstride(pixbuf);
	memset(pixels, 0, (size_t)stride * (size_t)h);
	nsvgRasterize(rast, image, tx, ty, scale, pixels, w, h, stride);
	if (ctx->prepared_func)
		ctx->prepared_func(pixbuf, NULL, ctx->user_data);
	if (ctx->updated_func)
		ctx->updated_func(pixbuf, 0, 0, w, h, ctx->user_data);
	ok = TRUE;
out:
	if (pixbuf)
		g_object_unref(pixbuf);
	if (rast)
		nsvgDeleteRasterizer(rast);
	if (image)
		nsvgDelete(image);
	g_byte_array_unref(ctx->data);
	g_free(ctx);
	return ok;
}

G_MODULE_EXPORT void fill_vtable(GdkPixbufModule *module);
G_MODULE_EXPORT void fill_info(GdkPixbufFormat *info);

G_MODULE_EXPORT void fill_vtable(GdkPixbufModule *module)
{
	module->begin_load = begin_load;
	module->stop_load = stop_load;
	module->load_increment = load_increment;
}

G_MODULE_EXPORT void fill_info(GdkPixbufFormat *info)
{
	/* "*": "<svg" anywhere in the first bytes (after <?xml ...?> and comments) */
	static GdkPixbufModulePattern signature[] = {
		{" <svg", "*    ", 100},
		{" <!DOCTYPE svg", "*             ", 100},
		{NULL, NULL, 0},
	};
	static gchar *mime_types[] = {"image/svg+xml", "image/svg", "image/svg-xml", "image/vnd.adobe.svg+xml",
				      "text/xml-svg", NULL};
	static gchar *extensions[] = {"svg", NULL};

	info->name = "svg";
	info->signature = signature;
	info->domain = "gdk-pixbuf";
	info->description = "Scalable Vector Graphics (NanoSVG)";
	info->mime_types = mime_types;
	info->extensions = extensions;
	info->flags = GDK_PIXBUF_FORMAT_SCALABLE | GDK_PIXBUF_FORMAT_THREADSAFE;
	info->license = "MIT";
}
