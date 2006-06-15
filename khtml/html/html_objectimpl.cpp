/**
 * This file is part of the DOM implementation for KDE.
 *
 * Copyright (C) 1999 Lars Knoll (knoll@kde.org)
 *           (C) 1999 Antti Koivisto (koivisto@kde.org)
 *           (C) 2000 Stefan Schimanski (1Stein@gmx.de)
 * Copyright (C) 2004 Apple Computer, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */
#include "html/html_objectimpl.h"

#include "khtml_part.h"
#include "dom/dom_string.h"
#include "misc/htmlhashes.h"
#include "khtmlview.h"
#include <qstring.h>
#include <qmap.h>
#include <kdebug.h>

#include "xml/dom_docimpl.h"
#include "css/cssstyleselector.h"
#include "css/csshelper.h"
#include "css/cssproperties.h"
#include "css/cssvalues.h"
#include "rendering/render_applet.h"
#include "rendering/render_frames.h"
#include "rendering/render_image.h"
#include "xml/dom2_eventsimpl.h"

#ifndef Q_WS_QWS // We don't have Java in Qt Embedded
#include "java/kjavaappletwidget.h"
#include "java/kjavaappletcontext.h"
#endif

#if APPLE_CHANGES
#include "KWQKHTMLPart.h"
#endif

using namespace DOM;
using namespace khtml;

// -------------------------------------------------------------------------

HTMLAppletElementImpl::HTMLAppletElementImpl(DocumentImpl *doc)
: HTMLElementImpl(doc)
, m_allParamsAvailable(false)
{
}

HTMLAppletElementImpl::~HTMLAppletElementImpl()
{
    // m_appletInstance should have been cleaned up in detach().
    assert(!m_appletInstance);
}

NodeImpl::Id HTMLAppletElementImpl::id() const
{
    return ID_APPLET;
}

bool HTMLAppletElementImpl::mapToEntry(NodeImpl::Id attr, MappedAttributeEntry& result) const
{
    switch (attr) {
        case ATTR_WIDTH:
        case ATTR_HEIGHT:
            result = eUniversal;
            return false;
        case ATTR_ALIGN:
            result = eReplaced; // Share with <img> since the alignment behavior is the same.
            return false;
        default:
            break;
    }
    
    return HTMLElementImpl::mapToEntry(attr, result);
}

void HTMLAppletElementImpl::parseHTMLAttribute(HTMLAttributeImpl *attr)
{
    switch (attr->id()) {
    case ATTR_ALT:
    case ATTR_ARCHIVE:
    case ATTR_CODE:
    case ATTR_CODEBASE:
    case ATTR_MAYSCRIPT:
    case ATTR_NAME:
    case ATTR_OBJECT:
        break;
    case ATTR_WIDTH:
        addCSSLength(attr, CSS_PROP_WIDTH, attr->value());
        break;
    case ATTR_HEIGHT:
        addCSSLength(attr, CSS_PROP_HEIGHT, attr->value());
        break;
    case ATTR_ALIGN:
	addHTMLAlignment(attr);
	break;
    default:
        HTMLElementImpl::parseHTMLAttribute(attr);
    }
}

bool HTMLAppletElementImpl::rendererIsNeeded(RenderStyle *style)
{
    return !getAttribute(ATTR_CODE).isNull();
}

RenderObject *HTMLAppletElementImpl::createRenderer(RenderArena *arena, RenderStyle *style)
{
#ifndef Q_WS_QWS // FIXME(E)? I don't think this is possible with Qt Embedded...
    KHTMLPart *part = getDocument()->part();

    if( part && part->javaEnabled() )
    {
	QMap<QString, QString> args;

	args.insert( "code", getAttribute(ATTR_CODE).string());
	DOMString codeBase = getAttribute(ATTR_CODEBASE);
	if(!codeBase.isNull())
	    args.insert( "codeBase", codeBase.string() );
	DOMString name = getDocument()->htmlMode() != DocumentImpl::XHtml ?
			 getAttribute(ATTR_NAME) : getAttribute(ATTR_ID);
	if(!name.isNull())
	    args.insert( "name", name.string() );
	DOMString archive = getAttribute(ATTR_ARCHIVE);
	if(!archive.isNull())
	    args.insert( "archive", archive.string() );

	args.insert( "baseURL", getDocument()->baseURL() );

        DOMString mayScript = getAttribute(ATTR_MAYSCRIPT);
        if (!mayScript.isNull())
            args.insert("mayScript", mayScript.string());

        // Other arguments (from <PARAM> tags) are added later.
        
        return new (getDocument()->renderArena()) RenderApplet(this, args);
    }

    // ### remove me. we should never show an empty applet, instead
    // render the alternative content given by the webpage
    return new (getDocument()->renderArena()) RenderEmptyApplet(this);
#else
    return 0;
#endif
}

bool HTMLAppletElementImpl::getMember(const QString & name, JType & type, QString & val) {
#if APPLE_CHANGES
    return false;
#else
#ifndef Q_WS_QWS // We don't have Java in Qt Embedded
    if ( !m_render || !m_render->isApplet() )
        return false;
    KJavaAppletWidget *w = static_cast<KJavaAppletWidget*>(static_cast<RenderApplet*>(m_render)->widget());
    return (w && w->applet() && w->applet()->getMember(name, type, val));
#else
    return false;
#endif
#endif
}

bool HTMLAppletElementImpl::callMember(const QString & name, const QStringList & args, JType & type, QString & val) {
#if APPLE_CHANGES
    return false;
#else
#ifndef Q_WS_QWS // We don't have Java in Qt Embedded
    if ( !m_render || !m_render->isApplet() )
        return false;
    KJavaAppletWidget *w = static_cast<KJavaAppletWidget*>(static_cast<RenderApplet*>(m_render)->widget());
    return (w && w->applet() && w->applet()->callMember(name, args, type, val));
#else
    return false;
#endif
#endif
}

#if APPLE_CHANGES
KJS::Bindings::Instance *HTMLAppletElementImpl::getAppletInstance() const
{
    KHTMLPart* part = getDocument()->part();
    if (!part || !part->javaEnabled())
        return 0;

    if (m_appletInstance)
        return m_appletInstance.get();
    
    RenderApplet *r = static_cast<RenderApplet*>(m_render);
    if (r) {
        r->createWidgetIfNecessary();
        if (r->widget()){
            // Call into the part (and over the bridge) to pull the Bindings::Instance
            // from the guts of the plugin.
            void *_view = r->widget()->getView();
            m_appletInstance = KWQ(part)->getAppletInstanceForView((NSView *)_view);
        }
    }
    return m_appletInstance.get();
}

void HTMLAppletElementImpl::closeRenderer()
{
    // The parser just reached </applet>, so all the params are available now.
    m_allParamsAvailable = true;
    if( m_render )
        m_render->setNeedsLayout(true); // This will cause it to create its widget & the Java applet
    
    HTMLElementImpl::closeRenderer();
}

void HTMLAppletElementImpl::detach()
{
    m_appletInstance = 0;

    HTMLElementImpl::detach();
}

bool HTMLAppletElementImpl::allParamsAvailable()
{
    return m_allParamsAvailable;
}
#endif

// -------------------------------------------------------------------------

HTMLEmbedElementImpl::HTMLEmbedElementImpl(DocumentImpl *doc)
: HTMLElementImpl(doc)
{
}

HTMLEmbedElementImpl::~HTMLEmbedElementImpl()
{
    // m_embedInstance should have been cleaned up in detach().
    assert(!m_embedInstance);
}

void HTMLEmbedElementImpl::detach()
{
    m_embedInstance = 0;

    HTMLElementImpl::detach();
}

NodeImpl::Id HTMLEmbedElementImpl::id() const
{
    return ID_EMBED;
}

#if APPLE_CHANGES
KJS::Bindings::Instance *HTMLEmbedElementImpl::getEmbedInstance() const
{
    KHTMLPart* part = getDocument()->part();
    if (!part)
        return 0;

    if (m_embedInstance)
        return m_embedInstance.get();
    
    RenderPartObject *r = static_cast<RenderPartObject*>(m_render);
    if (r) {
        if (r->widget()){
            // Call into the part (and over the bridge) to pull the Bindings::Instance
            // from the guts of the Java VM.
            void *_view = r->widget()->getView();
            m_embedInstance = KWQ(part)->getEmbedInstanceForView((NSView *)_view);
            // Applet may specified with <embed> tag.
            if (!m_embedInstance)
                m_embedInstance = KWQ(part)->getAppletInstanceForView((NSView *)_view);
        }
    }
    return m_embedInstance.get();
}
#endif

bool HTMLEmbedElementImpl::mapToEntry(NodeImpl::Id attr, MappedAttributeEntry& result) const
{
    switch (attr) {
        case ATTR_WIDTH:
        case ATTR_HEIGHT:
        case ATTR_BORDER:
        case ATTR_VSPACE:
        case ATTR_HSPACE:
        case ATTR_VALIGN:
        case ATTR_HIDDEN:
            result = eUniversal;
            return false;
        case ATTR_ALIGN:
            result = eReplaced; // Share with <img> since the alignment behavior is the same.
            return false;
        default:
            break;
    }
    
    return HTMLElementImpl::mapToEntry(attr, result);
}

void HTMLEmbedElementImpl::parseHTMLAttribute(HTMLAttributeImpl *attr)
{
  QString val = attr->value().string();
  
  int pos;
  switch ( attr->id() )
  {
     case ATTR_TYPE:
        serviceType = val.lower();
        pos = serviceType.find( ";" );
        if ( pos!=-1 )
            serviceType = serviceType.left( pos );
        break;
     case ATTR_CODE:
     case ATTR_SRC:
         url = khtml::parseURL(attr->value()).string();
         break;
     case ATTR_WIDTH:
        addCSSLength( attr, CSS_PROP_WIDTH, attr->value() );
        break;
     case ATTR_HEIGHT:
        addCSSLength( attr, CSS_PROP_HEIGHT, attr->value());
        break;
     case ATTR_BORDER:
        addCSSLength(attr, CSS_PROP_BORDER_WIDTH, attr->value());
        addCSSProperty( attr, CSS_PROP_BORDER_TOP_STYLE, CSS_VAL_SOLID );
        addCSSProperty( attr, CSS_PROP_BORDER_RIGHT_STYLE, CSS_VAL_SOLID );
        addCSSProperty( attr, CSS_PROP_BORDER_BOTTOM_STYLE, CSS_VAL_SOLID );
        addCSSProperty( attr, CSS_PROP_BORDER_LEFT_STYLE, CSS_VAL_SOLID );
        break;
     case ATTR_VSPACE:
        addCSSLength(attr, CSS_PROP_MARGIN_TOP, attr->value());
        addCSSLength(attr, CSS_PROP_MARGIN_BOTTOM, attr->value());
        break;
     case ATTR_HSPACE:
        addCSSLength(attr, CSS_PROP_MARGIN_LEFT, attr->value());
        addCSSLength(attr, CSS_PROP_MARGIN_RIGHT, attr->value());
        break;
     case ATTR_ALIGN:
	addHTMLAlignment(attr);
	break;
     case ATTR_VALIGN:
        addCSSProperty(attr, CSS_PROP_VERTICAL_ALIGN, attr->value());
        break;
     case ATTR_PLUGINPAGE:
     case ATTR_PLUGINSPAGE:
        pluginPage = val;
        break;
     case ATTR_HIDDEN:
        if (val.lower()=="yes" || val.lower()=="true") {
            // FIXME: Not dynamic, but it's not really important that such a rarely-used
            // feature work dynamically.
            addCSSLength( attr, CSS_PROP_WIDTH, "0" );
            addCSSLength( attr, CSS_PROP_HEIGHT, "0" );
        }
        break;
     default:
        HTMLElementImpl::parseHTMLAttribute( attr );
  }
}

bool HTMLEmbedElementImpl::rendererIsNeeded(RenderStyle *style)
{
    KHTMLPart *part = getDocument()->part();
    if (!part)
	return false;
    return part->pluginsEnabled() && parentNode()->id() != ID_OBJECT;
}

RenderObject *HTMLEmbedElementImpl::createRenderer(RenderArena *arena, RenderStyle *style)
{
    return new (arena) RenderPartObject(this);
}

void HTMLEmbedElementImpl::attach()
{
    HTMLElementImpl::attach();
    if (m_render) {
        static_cast<RenderPartObject*>(m_render)->updateWidget();
    }
}

bool HTMLEmbedElementImpl::isURLAttribute(AttributeImpl *attr) const
{
    return attr->id() == ATTR_SRC;
}

// -------------------------------------------------------------------------

HTMLObjectElementImpl::HTMLObjectElementImpl(DocumentImpl *doc) 
: HTMLElementImpl(doc)
, m_imageLoader(0)
{
    needWidgetUpdate = false;
    m_useFallbackContent = false;
    m_complete = false;
}

HTMLObjectElementImpl::~HTMLObjectElementImpl()
{
    // m_objectInstance should have been cleaned up in detach().
    assert(!m_objectInstance);
    
    delete m_imageLoader;
}

NodeImpl::Id HTMLObjectElementImpl::id() const
{
    return ID_OBJECT;
}

#if APPLE_CHANGES
KJS::Bindings::Instance *HTMLObjectElementImpl::getObjectInstance() const
{
    KHTMLPart* part = getDocument()->part();
    if (!part)
        return 0;

    if (m_objectInstance)
        return m_objectInstance.get();

    if (RenderObject *r = m_render) {
        if (r->isWidget()) {
            if (QWidget *widget = static_cast<RenderWidget *>(r)->widget()) {
                if (NSView *view = widget->getView())  {
                    // Call into the part (and over the bridge) to pull the Bindings::Instance
                    // from the guts of the plugin.
                    m_objectInstance = KWQ(part)->getObjectInstanceForView(view);
                    // Applet may specified with <object> tag.
                    if (!m_objectInstance)
                        m_objectInstance = KWQ(part)->getAppletInstanceForView(view);
                }
            }
        }
    }

    return m_objectInstance.get();
}
#endif

HTMLFormElementImpl *HTMLObjectElementImpl::form() const
{
  return 0;
}

bool HTMLObjectElementImpl::mapToEntry(NodeImpl::Id attr, MappedAttributeEntry& result) const
{
    switch (attr) {
        case ATTR_WIDTH:
        case ATTR_HEIGHT:
            result = eUniversal;
            return false;
        default:
            break;
    }
    
    return HTMLElementImpl::mapToEntry(attr, result);
}

void HTMLObjectElementImpl::parseHTMLAttribute(HTMLAttributeImpl *attr)
{
  QString val = attr->value().string();
  int pos;
  switch ( attr->id() )
  {
    case ATTR_TYPE:
      serviceType = val.lower();
      pos = serviceType.find( ";" );
      if ( pos!=-1 )
          serviceType = serviceType.left( pos );
      if (m_render)
          needWidgetUpdate = true;
      if (!isImageType() && m_imageLoader) {
          delete m_imageLoader;
          m_imageLoader = 0;
      }
      break;
    case ATTR_DATA:
      url = khtml::parseURL(  val ).string();
      if (m_render)
          needWidgetUpdate = true;
      if (m_render && isImageType()) {
          if (!m_imageLoader)
              m_imageLoader = new HTMLImageLoader(this);
          m_imageLoader->updateFromElement();
      }
      break;
    case ATTR_WIDTH:
      addCSSLength( attr, CSS_PROP_WIDTH, attr->value());
      break;
    case ATTR_HEIGHT:
      addCSSLength( attr, CSS_PROP_HEIGHT, attr->value());
      break;
    case ATTR_CLASSID:
      classId = val;
      if (m_render)
          needWidgetUpdate = true;
      break;
    case ATTR_ONLOAD: // ### support load/unload on object elements
        setHTMLEventListener(EventImpl::LOAD_EVENT,
	    getDocument()->createHTMLEventListener(attr->value().string(), this));
        break;
    case ATTR_ONUNLOAD:
        setHTMLEventListener(EventImpl::UNLOAD_EVENT,
	    getDocument()->createHTMLEventListener(attr->value().string(), this));
        break;
    default:
      HTMLElementImpl::parseHTMLAttribute( attr );
  }
}

DocumentImpl* HTMLObjectElementImpl::contentDocument() const
{
    // ###
    return 0;
}

bool HTMLObjectElementImpl::rendererIsNeeded(RenderStyle *style)
{
    if (m_useFallbackContent || isImageType())
        return HTMLElementImpl::rendererIsNeeded(style);

    KHTMLPart* part = getDocument()->part();
    if (!part || !part->pluginsEnabled()) {
        return false;
    }
#if APPLE_CHANGES
    // Eventually we will merge with the better version of this check on the tip of tree.
    // Until then, just leave it out.
#else
    KURL u = getDocument()->completeURL(url);
    for (KHTMLPart* part = w->part()->parentPart(); part; part = part->parentPart())
        if (part->url() == u) {
            return false;
        }
#endif
    return true;
}

RenderObject *HTMLObjectElementImpl::createRenderer(RenderArena *arena, RenderStyle *style)
{
    if (m_useFallbackContent)
        return RenderObject::createObject(this, style);
    if (isImageType())
        return new (arena) RenderImage(this);
    return new (arena) RenderPartObject(this);
}

void HTMLObjectElementImpl::attach()
{
    HTMLElementImpl::attach();

    if (m_render && !m_useFallbackContent) {
        if (isImageType()) {
            if (!m_imageLoader)
                m_imageLoader = new HTMLImageLoader(this);
            m_imageLoader->updateFromElement();
            if (renderer()) {
                RenderImage* imageObj = static_cast<RenderImage*>(renderer());
                imageObj->setImage(m_imageLoader->image());
            }
        } else {
            if (needWidgetUpdate) {
                // Set needWidgetUpdate to false before calling updateWidget because updateWidget may cause
                // this method or recalcStyle (which also calls updateWidget) to be called.
                needWidgetUpdate = false;
                static_cast<RenderPartObject*>(m_render)->updateWidget();
            } else {
                needWidgetUpdate = true;
                setChanged();
            }
        }
    }
}

void HTMLObjectElementImpl::closeRenderer()
{
    // The parser just reached </object>.
    setComplete(true);
    
    HTMLElementImpl::closeRenderer();
}

void HTMLObjectElementImpl::setComplete(bool complete)
{
    if (complete != m_complete) {
        m_complete = complete;
        if (complete && inDocument() && !m_useFallbackContent) {
            needWidgetUpdate = true;
            setChanged();
        }
    }
}

void HTMLObjectElementImpl::detach()
{
    if (attached() && m_render && !m_useFallbackContent) {
        // Update the widget the next time we attach (detaching destroys the plugin).
        needWidgetUpdate = true;
    }

    m_objectInstance = 0;

    HTMLElementImpl::detach();
}

void HTMLObjectElementImpl::recalcStyle(StyleChange ch)
{
    if (!m_useFallbackContent && needWidgetUpdate && m_render && !isImageType()) {
        // Set needWidgetUpdate to false before calling updateWidget because updateWidget may cause
        // this method or attach (which also calls updateWidget) to be called.
        needWidgetUpdate = false;
        static_cast<RenderPartObject*>(m_render)->updateWidget();
        dispatchHTMLEvent(EventImpl::LOAD_EVENT,false,false);
    }
    HTMLElementImpl::recalcStyle(ch);
}

void HTMLObjectElementImpl::childrenChanged()
{
    if (inDocument() && !m_useFallbackContent) {
        needWidgetUpdate = true;
        setChanged();
    }
}

bool HTMLObjectElementImpl::isURLAttribute(AttributeImpl *attr) const
{
    return (attr->id() == ATTR_DATA || (attr->id() == ATTR_USEMAP && attr->value().domString()[0] != '#'));
}

bool HTMLObjectElementImpl::isImageType()
{
    if (serviceType.isEmpty() && url.startsWith("data:")) {
        // Extract the MIME type from the data URL.
        int index = url.find(';');
        if (index == -1)
            index = url.find(',');
        if (index != -1) {
            int len = index - 5;
            if (len > 0)
                serviceType = url.mid(5, len);
            else
                serviceType = "text/plain"; // Data URLs with no MIME type are considered text/plain.
        }
    }

    return canRenderImageType(serviceType);
}

void HTMLObjectElementImpl::renderFallbackContent()
{
    if (m_useFallbackContent)
        return;

    // Mark ourselves as using the fallback content.
    m_useFallbackContent = true;

    // Now do a detach and reattach.    
    // FIXME: Style gets recalculated which is suboptimal.
    detach();
    attach();
}

// -------------------------------------------------------------------------

HTMLParamElementImpl::HTMLParamElementImpl(DocumentImpl *doc)
    : HTMLElementImpl(doc)
{
}

HTMLParamElementImpl::~HTMLParamElementImpl()
{
}

NodeImpl::Id HTMLParamElementImpl::id() const
{
    return ID_PARAM;
}

void HTMLParamElementImpl::parseHTMLAttribute(HTMLAttributeImpl *attr)
{
    switch( attr->id() )
    {
    case ATTR_ID:
        // Must call base class so that hasID bit gets set.
        HTMLElementImpl::parseHTMLAttribute(attr);
        if (getDocument()->htmlMode() != DocumentImpl::XHtml) break;
        // fall through
    case ATTR_NAME:
        m_name = attr->value();
        break;
    case ATTR_VALUE:
        m_value = attr->value();
        break;
    }
}

bool HTMLParamElementImpl::isURLAttribute(AttributeImpl *attr) const
{
    if (attr->id() == ATTR_VALUE) {
        AttributeImpl *attr = attributes()->getAttributeItem(ATTR_NAME);
        if (attr) {
            DOMString value = attr->value().string().lower();
            if (value == "src" || value == "movie" || value == "data") {
                return true;
            }
        }
    }
    return false;
}
