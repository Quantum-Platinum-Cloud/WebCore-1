/*
 * Copyright (C) 2003 Apple Computer, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#import "KWQKHTMLPart.h"

#import "htmltokenizer.h"
#import "html_documentimpl.h"
#import "render_canvas.h"
#import "render_frames.h"
#import "render_image.h"
#import "render_list.h"
#import "render_style.h"
#import "render_table.h"
#import "render_text.h"
#import "khtmlpart_p.h"
#import "khtmlview.h"
#import "kjs_window.h"
#import "misc/htmlattrs.h"
#import "csshelper.h"

#import "WebCoreBridge.h"
#import "WebCoreViewFactory.h"
#import "WebCoreDOMPrivate.h"

#import "KWQDummyView.h"
#import "KWQKJobClasses.h"
#import "KWQLogging.h"
#import "KWQPageState.h"
#import "KWQDOMNode.h"
#import "KWQWindowWidget.h"
#import <KWQPrinter.h>

#import "xml/dom2_eventsimpl.h"

#import <JavaScriptCore/property_map.h>

#undef _KWQ_TIMING

using DOM::DocumentImpl;
using DOM::DOMString;
using DOM::ElementImpl;
using DOM::EventImpl;
using DOM::Node;

using khtml::Cache;
using khtml::ChildFrame;
using khtml::Decoder;
using khtml::MouseDoubleClickEvent;
using khtml::MouseMoveEvent;
using khtml::MousePressEvent;
using khtml::MouseReleaseEvent;
using khtml::parseURL;
using khtml::PRE;
using khtml::RenderCanvas;
using khtml::RenderImage;
using khtml::RenderLayer;
using khtml::RenderListItem;
using khtml::RenderObject;
using khtml::RenderPart;
using khtml::RenderStyle;
using khtml::RenderTableCell;
using khtml::RenderText;
using khtml::RenderWidget;
using khtml::TextRunArray;
using khtml::VISIBLE;

using KIO::Job;

using KJS::SavedBuiltins;
using KJS::SavedProperties;
using KJS::ScheduledAction;
using KJS::Window;

using KParts::ReadOnlyPart;
using KParts::URLArgs;

NSEvent *KWQKHTMLPart::_currentEvent = nil;
NSResponder *KWQKHTMLPart::_firstResponderAtMouseDownTime = nil;

void KHTMLPart::completed()
{
    KWQ(this)->_completed.call();
}

void KHTMLPart::completed(bool arg)
{
    KWQ(this)->_completed.call(arg);
}

void KHTMLPart::nodeActivated(const Node &)
{
}

bool KHTMLPart::openURL(const KURL &URL)
{
    ASSERT_NOT_REACHED();
    return true;
}

void KHTMLPart::onURL(const QString &)
{
}

void KHTMLPart::setStatusBarText(const QString &status)
{
    KWQ(this)->setStatusBarText(status);
}

void KHTMLPart::started(Job *j)
{
    KWQ(this)->_started.call(j);
}

static void redirectionTimerMonitor(void *context)
{
    KWQKHTMLPart *kwq = static_cast<KWQKHTMLPart *>(context);
    kwq->redirectionTimerStartedOrStopped();
}

KWQKHTMLPart::KWQKHTMLPart()
    : _started(this, SIGNAL(started(KIO::Job *)))
    , _completed(this, SIGNAL(completed()))
    , _completedWithBool(this, SIGNAL(completed(bool)))
    , _mouseDownView(nil)
    , _sendingEventToSubview(false)
    , _mouseDownMayStartDrag(false)
    , _mouseDownMayStartSelect(false)
    , _formValuesAboutToBeSubmitted(nil)
    , _formAboutToBeSubmitted(nil)
    , _windowWidget(NULL)
    , _usesInactiveTextBackgroundColor(false)
{
    // Must init the cache before connecting to any signals
    Cache::init();

    // The widget is made outside this class in our case.
    KHTMLPart::init( 0, DefaultGUI );

    mutableInstances().prepend(this);
    d->m_redirectionTimer.setMonitor(redirectionTimerMonitor, this);
}

KWQKHTMLPart::~KWQKHTMLPart()
{
    mutableInstances().remove(this);
    if (d->m_view) {
	d->m_view->deref();
    }
    [_formValuesAboutToBeSubmitted release];
    [_formAboutToBeSubmitted release];
    delete _windowWidget;
}

void KWQKHTMLPart::setSettings (KHTMLSettings *settings)
{
    d->m_settings = settings;
}

QString KWQKHTMLPart::generateFrameName()
{
    return QString::fromNSString([_bridge generateFrameName]);
}

void KWQKHTMLPart::provisionalLoadStarted()
{
    // we don't want to wait until we get an actual http response back
    // to cancel pending redirects, otherwise they might fire before
    // that happens.
    cancelRedirection(true);
}

bool KWQKHTMLPart::openURL(const KURL &url)
{
    // FIXME: The lack of args here to get the reload flag from
    // indicates a problem in how we use KHTMLPart::processObjectRequest,
    // where we are opening the URL before the args are set up.
    [_bridge loadURL:url.getNSURL()
            referrer:[_bridge referrer]
              reload:NO
              target:nil
     triggeringEvent:nil
                form:nil
          formValues:nil];
    return true;
}

void KWQKHTMLPart::openURLRequest(const KURL &url, const URLArgs &args)
{
    [_bridge loadURL:url.getNSURL()
            referrer:[_bridge referrer]
              reload:args.reload
              target:args.frameName.getNSString()
     triggeringEvent:nil
                form:nil
          formValues:nil];
}

void KWQKHTMLPart::didNotOpenURL(const KURL &URL)
{
    if (_submittedFormURL == URL) {
        _submittedFormURL = KURL();
    }
}

// Scans logically forward from "start", including any child frames
static HTMLFormElementImpl *scanForForm(NodeImpl *start)
{
    NodeImpl *n;
    for (n = start; n; n = n->traverseNextNode()) {
        NodeImpl::Id nodeID = idFromNode(n);
        if (nodeID == ID_FORM) {
            return static_cast<HTMLFormElementImpl *>(n);
        } else if (n->isHTMLElement()
                   && static_cast<HTMLElementImpl *>(n)->isGenericFormElement()) {
            return static_cast<HTMLGenericFormElementImpl *>(n)->form();
        } else if (nodeID == ID_FRAME || nodeID == ID_IFRAME) {
            NodeImpl *childDoc = static_cast<HTMLFrameElementImpl *>(n)->contentDocument();
            HTMLFormElementImpl *frameResult = scanForForm(childDoc);
            if (frameResult) {
                return frameResult;
            }
        }
    }
    return 0;
}

// We look for either the form containing the current focus, or for one immediately after it
HTMLFormElementImpl *KWQKHTMLPart::currentForm() const
{
    // start looking either at the active (first responder) node, or where the selection is
    NodeImpl *start = activeNode().handle();
    if (!start) {
        start = selectionStart();
    }

    // try walking up the node tree to find a form element
    NodeImpl *n;
    for (n = start; n; n = n->parentNode()) {
        if (idFromNode(n) == ID_FORM) {
            return static_cast<HTMLFormElementImpl *>(n);
        } else if (n->isHTMLElement()
                   && static_cast<HTMLElementImpl *>(n)->isGenericFormElement()) {
            return static_cast<HTMLGenericFormElementImpl *>(n)->form();
        }
    }

    // try walking forward in the node tree to find a form element
    if (!start) {
        start = xmlDocImpl();
    }
    return scanForForm(start);
}

// Either get cached regexp or build one that matches any of the labels.
// The regexp we build is of the form:  (STR1|STR2|STRN)
QRegExp *regExpForLabels(NSArray *labels)
{
    // Parallel arrays that we use to cache regExps.  In practice the number of expressions
    // that the app will use is equal to the number of locales is used in searching.
    static const unsigned int regExpCacheSize = 4;
    static NSMutableArray *regExpLabels = nil;
    static QPtrList <QRegExp> regExps;
    static QRegExp wordRegExp = QRegExp("\\w");

    QRegExp *result;
    if (!regExpLabels) {
        regExpLabels = [[NSMutableArray alloc] initWithCapacity:regExpCacheSize];
    }
    unsigned int cacheHit = [regExpLabels indexOfObject:labels];
    if (cacheHit != NSNotFound) {
        result = regExps.at(cacheHit);
    } else {
        QString pattern("(");
        unsigned int numLabels = [labels count];
        unsigned int i;
        for (i = 0; i < numLabels; i++) {
            QString label = QString::fromNSString([labels objectAtIndex:i]);

            bool startsWithWordChar = false;
            bool endsWithWordChar = false;
            if (label.length() != 0) {
                startsWithWordChar = wordRegExp.search(label.at(0)) >= 0;
                endsWithWordChar = wordRegExp.search(label.at(label.length() - 1)) >= 0;
            }
            
            if (i != 0) {
                pattern.append("|");
            }
            // Search for word boundaries only if label starts/ends with "word characters".
            // If we always searched for word boundaries, this wouldn't work for languages
            // such as Japanese.
            if (startsWithWordChar) {
                pattern.append("\\b");
            }
            pattern.append(label);
            if (endsWithWordChar) {
                pattern.append("\\b");
            }
        }
        pattern.append(")");
        result = new QRegExp(pattern, false);
    }

    // add regexp to the cache, making sure it is at the front for LRU ordering
    if (cacheHit != 0) {
        if (cacheHit != NSNotFound) {
            // remove from old spot
            [regExpLabels removeObjectAtIndex:cacheHit];
            regExps.remove(cacheHit);
        }
        // add to start
        [regExpLabels insertObject:labels atIndex:0];
        regExps.insert(0, result);
        // trim if too big
        if ([regExpLabels count] > regExpCacheSize) {
            [regExpLabels removeObjectAtIndex:regExpCacheSize];
            QRegExp *last = regExps.last();
            regExps.removeLast();
            delete last;
        }
    }
    return result;
}

NSString *KWQKHTMLPart::searchForLabelsAboveCell(QRegExp *regExp, HTMLTableCellElementImpl *cell)
{
    RenderTableCell *cellRenderer = static_cast<RenderTableCell *>(cell->renderer());
    RenderTableCell *cellAboveRenderer = cellRenderer->table()->cellAbove(cellRenderer);

    if (cellAboveRenderer) {
        HTMLTableCellElementImpl *aboveCell =
            static_cast<HTMLTableCellElementImpl *>(cellAboveRenderer->element());

        if (aboveCell) {
            // search within the above cell we found for a match
            for (NodeImpl *n = aboveCell->firstChild(); n; n = n->traverseNextNode(aboveCell)) {
                if (idFromNode(n) == ID_TEXT
                    && n->renderer() && n->renderer()->style()->visibility() == VISIBLE)
                {
                    // For each text chunk, run the regexp
                    QString nodeString = n->nodeValue().string();
                    int pos = regExp->searchRev(nodeString);
                    if (pos >= 0) {
                        return nodeString.mid(pos, regExp->matchedLength()).getNSString();
                    }
                }
            }
        }
    }
    // Any reason in practice to search all cells in that are above cell?
    return nil;
}

NSString *KWQKHTMLPart::searchForLabelsBeforeElement(NSArray *labels, ElementImpl *element)
{
    QRegExp *regExp = regExpForLabels(labels);
    // We stop searching after we've seen this many chars
    const unsigned int charsSearchedThreshold = 500;
    // This is the absolute max we search.  We allow a little more slop than
    // charsSearchedThreshold, to make it more likely that we'll search whole nodes.
    const unsigned int maxCharsSearched = 600;
    // If the starting element is within a table, the cell that contains it
    HTMLTableCellElementImpl *startingTableCell = 0;
    bool searchedCellAbove = false;

    // walk backwards in the node tree, until another element, or form, or end of tree
    int unsigned lengthSearched = 0;
    NodeImpl *n;
    for (n = element->traversePreviousNode();
         n && lengthSearched < charsSearchedThreshold;
         n = n->traversePreviousNode())
    {
        NodeImpl::Id nodeID = idFromNode(n);
        if (nodeID == ID_FORM
            || (n->isHTMLElement()
                && static_cast<HTMLElementImpl *>(n)->isGenericFormElement()))
        {
            // We hit another form element or the start of the form - bail out
            break;
        } else if (nodeID == ID_TD && !startingTableCell) {
            startingTableCell = static_cast<HTMLTableCellElementImpl *>(n);
        } else if (nodeID == ID_TR && startingTableCell) {
            NSString *result = searchForLabelsAboveCell(regExp, startingTableCell);
            if (result) {
                return result;
            }
            searchedCellAbove = true;
        } else if (nodeID == ID_TEXT
                   && n->renderer() && n->renderer()->style()->visibility() == VISIBLE)
        {
            // For each text chunk, run the regexp
            QString nodeString = n->nodeValue().string();
            // add 100 for slop, to make it more likely that we'll search whole nodes
            if (lengthSearched + nodeString.length() > maxCharsSearched) {
                nodeString = nodeString.right(charsSearchedThreshold - lengthSearched);
            }
            int pos = regExp->searchRev(nodeString);
            if (pos >= 0) {
                return nodeString.mid(pos, regExp->matchedLength()).getNSString();
            } else {
                lengthSearched += nodeString.length();
            }
        }
    }

    // If we started in a cell, but bailed because we found the start of the form or the
    // previous element, we still might need to search the row above us for a label.
    if (startingTableCell && !searchedCellAbove) {
         return searchForLabelsAboveCell(regExp, startingTableCell);
    } else {
        return nil;
    }
}

NSString *KWQKHTMLPart::matchLabelsAgainstElement(NSArray *labels, ElementImpl *element)
{
    QString name = element->getAttribute(ATTR_NAME).string();
    // Make numbers in field names behave like word boundaries, e.g., "address2"
    name.replace(QRegExp("[[:digit:]]"), " ");
    
    QRegExp *regExp = regExpForLabels(labels);
    // Use the largest match we can find in the whole name string
    int pos;
    int length;
    int bestPos = -1;
    int bestLength = -1;
    int start = 0;
    do {
        pos = regExp->search(name, start);
        if (pos != -1) {
            length = regExp->matchedLength();
            if (length >= bestLength) {
                bestPos = pos;
                bestLength = length;
            }
            start = pos+1;
        }
    } while (pos != -1);

    if (bestPos != -1) {
        return name.mid(bestPos, bestLength).getNSString();
    } else {
        return nil;
    }
}

// Search from the end of the currently selected location if we are first responder, or from
// the beginning of the document if nothing is selected or we're not first responder.
bool KWQKHTMLPart::findString(NSString *string, bool forward, bool caseFlag, bool wrapFlag)
{
    QString target = QString::fromNSString(string);
    bool result;
    // start on the correct edge of the selection, search to end
    NodeImpl *selStart = selectionStart();
    int selStartOffset = selectionStartOffset();
    NodeImpl *selEnd = selectionEnd();
    int selEndOffset = selectionEndOffset();
    if (selStart) {
        if (forward) {
            // point to last char of selection, find will start right afterwards
            findTextBegin(selEnd, selEndOffset-1);
        } else {
            // point to first char of selection, find will start right before
            findTextBegin(selStart, selStartOffset);
        }
    } else {
        findTextBegin();
    }
    result = findTextNext(target, forward, caseFlag, FALSE);
    if (!result && wrapFlag) {
        // start back at the other end, search the rest
        findTextBegin();
        result = findTextNext(target, forward, caseFlag, FALSE);
        // if we got back to the same place we started, that doesn't count as success
        if (result
            && selStart == selectionStart()
            && selStartOffset == selectionStartOffset())
        {
            result = false;
        }
    }

    // khtml took care of moving the selection, but we need to move first responder too,
    // so the selection is primary.  We also need to make the selection visible, since we
    // cut the implementation of this in khtml_part.
    if (result) {
        jumpToSelection();
    }
    return result;
}

void KWQKHTMLPart::clearRecordedFormValues()
{
    [_formValuesAboutToBeSubmitted release];
    _formValuesAboutToBeSubmitted = nil;
    [_formAboutToBeSubmitted release];
    _formAboutToBeSubmitted = nil;
}

void KWQKHTMLPart::recordFormValue(const QString &name, const QString &value, HTMLFormElementImpl *element)
{
    if (!_formValuesAboutToBeSubmitted) {
        _formValuesAboutToBeSubmitted = [[NSMutableDictionary alloc] init];
        ASSERT(!_formAboutToBeSubmitted);
        _formAboutToBeSubmitted = [[WebCoreDOMElement elementWithImpl:element] retain];
    } else {
        ASSERT([_formAboutToBeSubmitted elementImpl] == element);
    }
    [_formValuesAboutToBeSubmitted setObject:value.getNSString() forKey:name.getNSString()];
}

void KWQKHTMLPart::submitForm(const KURL &url, const URLArgs &args)
{
    // The form multi-submit logic here is only right when we are submitting a form that affects this frame.
    // Eventually when we find a better fix we can remove this altogether.
    WebCoreBridge *target = args.frameName.isEmpty() ? _bridge : [_bridge findFrameNamed:args.frameName.getNSString()];
    KHTMLPart *targetPart = [target part];
    bool willReplaceThisFrame = false;
    for (KHTMLPart *p = this; p; p = p->parentPart()) {
        if (p == targetPart) {
            willReplaceThisFrame = true;
            break;
        }
    }
    if (willReplaceThisFrame) {
        // We do not want to submit more than one form from the same page,
        // nor do we want to submit a single form more than once.
        // This flag prevents these from happening.
        // Note that the flag is reset in setView()
        // since this part may get reused if it is pulled from the b/f cache.
        if (_submittedFormURL == url) {
            return;
        }
        _submittedFormURL = url;
    }

    if (!args.doPost()) {
        [_bridge loadURL:url.getNSURL()
	        referrer:[_bridge referrer] 
                  reload:args.reload
  	          target:args.frameName.getNSString()
         triggeringEvent:_currentEvent
                    form:_formAboutToBeSubmitted
              formValues:_formValuesAboutToBeSubmitted];
    } else {
        ASSERT(args.contentType().startsWith("Content-Type: "));
        [_bridge postWithURL:url.getNSURL()
	            referrer:[_bridge referrer] 
                      target:args.frameName.getNSString()
                        data:[NSData dataWithBytes:args.postData.data() length:args.postData.size()]
                 contentType:args.contentType().mid(14).getNSString()
             triggeringEvent:_currentEvent
                        form:_formAboutToBeSubmitted
                  formValues:_formValuesAboutToBeSubmitted];
    }
    clearRecordedFormValues();
}

void KWQKHTMLPart::setEncoding(const QString &name, bool userChosen)
{
    if (!d->m_workingURL.isEmpty()) {
        receivedFirstData();
    }
    d->m_encoding = name;
    d->m_haveEncoding = userChosen;
}

void KWQKHTMLPart::addData(const char *bytes, int length)
{
    ASSERT(d->m_workingURL.isEmpty());
    ASSERT(d->m_doc);
    ASSERT(d->m_doc->parsing());
    write(bytes, length);
}

void KHTMLPart::frameDetached()
{
    [KWQ(this)->bridge() frameDetached];

    // FIXME: There may be a better place to do this that works for KHTML too.
    FrameList& parentFrames = parentPart()->d->m_frames;
    FrameIt end = parentFrames.end();
    for (FrameIt it = parentFrames.begin(); it != end; ++it) {
        if ((*it).m_part == this) {
            parentFrames.remove(it);
            deref();
            break;
        }
    }
}

void KWQKHTMLPart::urlSelected(const KURL &url, int button, int state, const URLArgs &args)
{
    [_bridge loadURL:url.getNSURL()
            referrer:[_bridge referrer]
              reload:args.reload
              target:args.frameName.getNSString()
     triggeringEvent:_currentEvent
                form:nil
          formValues:nil];
}

class KWQPluginPart : public ReadOnlyPart
{
    virtual bool openURL(const KURL &) { return true; }
    virtual bool closeURL() { return true; }
};

ReadOnlyPart *KWQKHTMLPart::createPart(const ChildFrame &child, const KURL &url, const QString &mimeType)
{
    BOOL needFrame = [_bridge frameRequiredForMIMEType: mimeType.getNSString()];
    if (child.m_type == ChildFrame::Object && !needFrame) {
        NSMutableArray *attributesArray = [NSMutableArray arrayWithCapacity:child.m_params.count()];
        for (uint i = 0; i < child.m_params.count(); i++) {
            [attributesArray addObject:child.m_params[i].getNSString()];
        }
        
        KWQPluginPart *newPart = new KWQPluginPart;
        newPart->setWidget(new QWidget([_bridge viewForPluginWithURL:url.getNSURL()
                                                          attributes:attributesArray
                                                             baseURL:KURL(d->m_doc->baseURL()).getNSURL()
                                                            MIMEType:child.m_args.serviceType.getNSString()]));
        return newPart;
    } else {
        LOG(Frames, "name %s", child.m_name.ascii());
        BOOL allowsScrolling = YES;
        int marginWidth = -1;
        int marginHeight = -1;
        if (child.m_type != ChildFrame::Object) {
            HTMLIFrameElementImpl *o = static_cast<HTMLIFrameElementImpl *>(child.m_frame->element());
            allowsScrolling = o->scrollingMode() != QScrollView::AlwaysOff;
            marginWidth = o->getMarginWidth();
            marginHeight = o->getMarginHeight();
        }
        WebCoreBridge *childBridge = [_bridge createChildFrameNamed:child.m_name.getNSString()
                                                            withURL:url.getNSURL()
                                                         renderPart:child.m_frame
                                                    allowsScrolling:allowsScrolling
                                                        marginWidth:marginWidth
                                                       marginHeight:marginHeight];
	// This call needs to return an object with a ref, since the caller will expect to own it.
	// childBridge owns the only ref so far.
	[childBridge part]->ref();
        return [childBridge part];
    }
}
    
void KWQKHTMLPart::setView(KHTMLView *view)
{
    // Detach the document now, so any onUnload handlers get run - if
    // we wait until the view is destroyed, then things won't be
    // hooked up enough for some JavaScript calls to work.
    if (d->m_doc && view == NULL) {
	d->m_doc->detach();
    }

    if (view) {
	view->ref();
    }
    if (d->m_view) {
	d->m_view->deref();
    }
    d->m_view = view;
    setWidget(view);
    
    // Only one form submission is allowed per view of a part.
    // Since this part may be getting reused as a result of being
    // pulled from the back/forward cache, reset this flag.
    _submittedFormURL = KURL();
}

KHTMLView *KWQKHTMLPart::view() const
{
    return d->m_view;
}

void KWQKHTMLPart::setTitle(const DOMString &title)
{
    QString text = title.string();
    text.replace('\\', backslashAsCurrencySymbol());
    [_bridge setTitle:text.getNSString()];
}

void KWQKHTMLPart::setStatusBarText(const QString &status)
{
    QString text = status;
    text.replace('\\', backslashAsCurrencySymbol());
    [_bridge setStatusText:text.getNSString()];
}

void KWQKHTMLPart::scheduleClose()
{
    [_bridge closeWindowSoon];
}

void KWQKHTMLPart::unfocusWindow()
{
    [_bridge unfocusWindow];
}

void KWQKHTMLPart::jumpToSelection()
{
    // Assumes that selection will only ever be text nodes. This is currently
    // true, but will it always be so?
    if (!d->m_selectionStart.isNull()) {
        RenderText *rt = dynamic_cast<RenderText *>(d->m_selectionStart.handle()->renderer());
        if (rt) {
            int x = 0, y = 0;
            rt->posOfChar(d->m_startOffset, x, y);
            // The -50 offset is copied from KHTMLPart::findTextNext, which sets the contents position
            // after finding a matched text string.
           d->m_view->setContentsPos(x - 50, y - 50);
        }
/*
        I think this would be a better way to do this, to avoid needless horizontal scrolling,
        but it is not feasible until selectionRect() returns a tighter rect around the
        selected text.  Right now it works at element granularity.
 
        NSView *docView = d->m_view->getDocumentView();

        NSRect selRect = NSRect(selectionRect());
        NSRect visRect = [docView visibleRect];
        if (!NSContainsRect(visRect, selRect)) {
            // pad a bit so we overscroll slightly
            selRect = NSInsetRect(selRect, -10.0, -10.0);
            selRect = NSIntersectionRect(selRect, [docView bounds]);
            [docView scrollRectToVisible:selRect];
        }
*/
    }
}

void KWQKHTMLPart::redirectionTimerStartedOrStopped()
{
    // Don't report history navigations, just actual redirection.
    if (d->m_scheduledRedirection == historyNavigationScheduled) {
        return;
    }
    
    if (d->m_redirectionTimer.isActive()) {
        [_bridge reportClientRedirectToURL:KURL(d->m_redirectURL).getNSURL()
                                     delay:d->m_delayRedirect
                                  fireDate:[d->m_redirectionTimer.getNSTimer() fireDate]
                               lockHistory:d->m_redirectLockHistory
                               isJavaScriptFormAction:d->m_executingJavaScriptFormAction];
    } else {
        [_bridge reportClientRedirectCancelled:d->m_cancelWithLoadInProgress];
    }
}

void KWQKHTMLPart::paint(QPainter *p, const QRect &rect)
{
#ifndef NDEBUG
    bool isPrinting = (p->device()->devType() == QInternal::Printer);
    if (!isPrinting && xmlDocImpl() && !xmlDocImpl()->ownerElement()) {
        p->fillRect(rect.x(), rect.y(), rect.width(), rect.height(), QColor(0xFF, 0, 0));
    }
#endif

    if (renderer()) {
        renderer()->layer()->paint(p, rect.x(), rect.y(), rect.width(), rect.height(), false);
    } else {
        ERROR("called KWQKHTMLPart::paint with nil renderer");
    }
}

void KWQKHTMLPart::paintSelectionOnly(QPainter *p, const QRect &rect)
{
    if (renderer()) {
        renderer()->layer()->paint(p, rect.x(), rect.y(), rect.width(), rect.height(), true);
    } else {
        ERROR("called KWQKHTMLPart::paintSelectionOnly with nil renderer");
    }
}

void KWQKHTMLPart::adjustPageHeight(float *newBottom, float oldTop, float oldBottom, float bottomLimit)
{
    RenderCanvas *root = static_cast<RenderCanvas *>(xmlDocImpl()->renderer());
    if (root) {
        // Use a printer device, with painting disabled for the pagination phase
        QPainter painter(true);
        painter.setPaintingDisabled(true);

        root->setTruncatedAt((int)floor(oldBottom));
        root->layer()->paint(&painter, 0, (int)floor(oldTop),
                             root->docWidth(), (int)ceil(oldBottom-oldTop), false);
        *newBottom = root->bestTruncatedAt();
        if (*newBottom == 0) {
            *newBottom = oldBottom;
        }
    } else {
        *newBottom = oldBottom;
    }
}

RenderObject *KWQKHTMLPart::renderer()
{
    DocumentImpl *doc = xmlDocImpl();
    return doc ? doc->renderer() : 0;
}

QString KWQKHTMLPart::userAgent() const
{
    NSString *us = [_bridge userAgentForURL:m_url.getNSURL()];
         
    if (us)
        return QString::fromNSString(us);
    return QString();
}

QString KWQKHTMLPart::mimeTypeForFileName(const QString &fileName) const
{
    NSString *ns = fileName.getNSString();
    NSString *mimeType = [_bridge MIMETypeForPath:ns];
    return QString::fromNSString(mimeType);
}

NSView *KWQKHTMLPart::nextKeyViewInFrame(NodeImpl *node, KWQSelectionDirection direction)
{
    DocumentImpl *doc = xmlDocImpl();
    if (!doc) {
        return nil;
    }
    for (;;) {
        node = direction == KWQSelectingNext
            ? doc->nextFocusNode(node) : doc->previousFocusNode(node);
        if (!node) {
            return nil;
        }
        RenderWidget *renderWidget = dynamic_cast<RenderWidget *>(node->renderer());
        if (renderWidget) {
            QWidget *widget = renderWidget->widget();
            KHTMLView *childFrameWidget = dynamic_cast<KHTMLView *>(widget);
            if (childFrameWidget) {
                NSView *view = KWQ(childFrameWidget->part())->nextKeyViewInFrame(0, direction);
                if (view) {
                    return view;
                }
            } else if (widget) {
                NSView *view = widget->getView();
                // AppKit won't be able to handle scrolling and making us the first responder
                // well unless we are actually installed in the correct place. KHTML only does
                // that for visible widgets, so we need to do it explicitly here.
                int x, y;
                if (view && renderWidget->absolutePosition(x, y)) {
                    renderWidget->view()->addChild(widget, x, y);
                    return view;
                }
            }
        }
    }
}

ChildFrame *KWQKHTMLPart::childFrameForPart(const ReadOnlyPart *part) const
{
    FrameIt it = d->m_frames.begin();
    FrameIt end = d->m_frames.end();
    for (; it != end; ++it) {
	if ((*it).m_part == part) {
            return &*it;
        }
    }
    it = d->m_objects.begin();
    end = d->m_objects.end();
    for (; it != end; ++it) {
	if ((*it).m_part == part) {
            return &*it;
        }
    }
    return 0;
}

NSView *KWQKHTMLPart::nextKeyViewInFrameHierarchy(NodeImpl *node, KWQSelectionDirection direction)
{
    NSView *next = nextKeyViewInFrame(node, direction);
    if (next) {
        return next;
    }
    
    KWQKHTMLPart *parent = KWQ(parentPart());
    if (parent) {
        next = parent->nextKeyView(parent->childFrameForPart(this)->m_frame->element(), direction);
        if (next) {
            return next;
        }
    }
    
    return nil;
}

NSView *KWQKHTMLPart::nextKeyView(NodeImpl *node, KWQSelectionDirection direction)
{
    NSView *next = nextKeyViewInFrameHierarchy(node, direction);
    if (next) {
        return next;
    }

    // Look at views from the top level part up, looking for a next key view that we can use.
    next = direction == KWQSelectingNext
        ? [_bridge nextKeyViewOutsideWebFrameViews]
        : [_bridge previousKeyViewOutsideWebFrameViews];
    if (next) {
        return next;
    }
    
    // If all else fails, make a loop by starting from 0.
    return nextKeyViewInFrameHierarchy(0, direction);
}

NSView *KWQKHTMLPart::nextKeyViewForWidget(QWidget *startingWidget, KWQSelectionDirection direction)
{
    // Use the event filter object to figure out which RenderWidget owns this QWidget and get to the DOM.
    // Then get the next key view in the order determined by the DOM.
    NodeImpl *node = nodeForWidget(startingWidget);
    ASSERT(node);
    return partForNode(node)->nextKeyView(node, direction);
}

bool KWQKHTMLPart::currentEventIsMouseDownInWidget(QWidget *candidate)
{
    switch ([[NSApp currentEvent] type]) {
        case NSLeftMouseDown:
        case NSRightMouseDown:
        case NSOtherMouseDown:
            break;
        default:
            return NO;
    }

    NodeImpl *node = nodeForWidget(candidate);
    ASSERT(node);
    return partForNode(node)->nodeUnderMouse() == node;
}


QMap<int, ScheduledAction*> *KWQKHTMLPart::pauseActions(const void *key)
{
    if (d->m_doc && d->m_jscript) {
        Window *w = Window::retrieveWindow(this);
        if (w && w->hasTimeouts()) {
            return w->pauseTimeouts(key);
        }
    }
    return 0;
}

void KWQKHTMLPart::resumeActions(QMap<int, ScheduledAction*> *actions, const void *key)
{
    if (d->m_doc && d->m_jscript && d->m_bJScriptEnabled) {
        Window *w = Window::retrieveWindow(this);
        if (w) {
            w->resumeTimeouts(actions, key);
        }
    }
}

bool KWQKHTMLPart::canCachePage()
{
    // Only save page state if:
    // 1.  We're not a frame or frameset.
    // 2.  The page has no unload handler.
    // 3.  The page has no password fields.
    // 4.  The URL for the page is https.
    if (d->m_frames.count() ||
        parentPart() ||
        m_url.protocol().startsWith("https") || 
	(d->m_doc && (d->m_doc->hasWindowEventListener(EventImpl::UNLOAD_EVENT) ||
		      d->m_doc->hasPasswordField()))) {
        return false;
    }
    return true;
}

void KWQKHTMLPart::saveWindowProperties(SavedProperties *windowProperties)
{
    Window *window = Window::retrieveWindow(this);
    if (window)
        window->saveProperties(*windowProperties);
}

void KWQKHTMLPart::saveLocationProperties(SavedProperties *locationProperties)
{
    Window *window = Window::retrieveWindow(this);
    if (window)
        window->location()->saveProperties(*locationProperties);
}

void KWQKHTMLPart::restoreWindowProperties(SavedProperties *windowProperties)
{
    Window *window = Window::retrieveWindow(this);
    if (window)
        window->restoreProperties(*windowProperties);
}

void KWQKHTMLPart::restoreLocationProperties(SavedProperties *locationProperties)
{
    Window *window = Window::retrieveWindow(this);
    if (window)
        window->location()->restoreProperties(*locationProperties);
}

void KWQKHTMLPart::saveInterpreterBuiltins(SavedBuiltins &interpreterBuiltins)
{
    if (jScript() && jScript()->interpreter()) {
	jScript()->interpreter()->saveBuiltins(interpreterBuiltins);
    }
}

void KWQKHTMLPart::restoreInterpreterBuiltins(const SavedBuiltins &interpreterBuiltins)
{
    if (jScript() && jScript()->interpreter()) {
	jScript()->interpreter()->restoreBuiltins(interpreterBuiltins);
    }
}

void KWQKHTMLPart::openURLFromPageCache(KWQPageState *state)
{
    DocumentImpl *doc = [state document];
    RenderObject *renderer = [state renderer];
    KURL *url = [state URL];
    SavedProperties *windowProperties = [state windowProperties];
    SavedProperties *locationProperties = [state locationProperties];
    SavedBuiltins *interpreterBuiltins = [state interpreterBuiltins];
    QMap<int, ScheduledAction*> *actions = [state pausedActions];
    
    cancelRedirection();

    // We still have to close the previous part page.
    if (!d->m_restored){
        closeURL();
    }
            
    d->m_bComplete = false;
    
    // Don't re-emit the load event.
    d->m_bLoadEventEmitted = true;
    
    // delete old status bar msg's from kjs (if it _was_ activated on last URL)
    if( d->m_bJScriptEnabled )
    {
        d->m_kjsStatusBarText = QString::null;
        d->m_kjsDefaultStatusBarText = QString::null;
    }

    ASSERT (url);
    
    m_url = *url;
    
    // initializing m_url to the new url breaks relative links when opening such a link after this call and _before_ begin() is called (when the first
    // data arrives) (Simon)
    if(m_url.protocol().startsWith( "http" ) && !m_url.host().isEmpty() && m_url.path().isEmpty()) {
        m_url.setPath("/");
        emit d->m_extension->setLocationBarURL( m_url.prettyURL() );
    }
    
    // copy to m_workingURL after fixing m_url above
    d->m_workingURL = m_url;
        
    emit started( 0L );
    
    // -----------begin-----------
    clear();

    doc->restoreRenderer(renderer);
    
    d->m_bCleared = false;
    d->m_cacheId = 0;
    d->m_bComplete = false;
    d->m_bLoadEventEmitted = false;
    d->m_referrer = m_url.url();
    
    setView(doc->view());
    
    d->m_doc = doc;
    d->m_doc->ref();
    
    Decoder *decoder = doc->decoder();
    if (decoder) {
        decoder->ref();
    }
    if (d->m_decoder) {
        d->m_decoder->deref();
    }
    d->m_decoder = decoder;

    updatePolicyBaseURL();
        
    restoreWindowProperties (windowProperties);
    restoreLocationProperties (locationProperties);
    restoreInterpreterBuiltins (*interpreterBuiltins);

    if (actions)
        resumeActions (actions, state);
    
    checkCompleted();
}

WebCoreBridge *KWQKHTMLPart::bridgeForWidget(const QWidget *widget)
{
    ASSERT_ARG(widget, widget);

    NodeImpl *node = nodeForWidget(widget);
    if (node) {
	return partForNode(node)->bridge() ;
    }
    
    // Assume all widgets are either form controls, or KHTMLViews.
    const KHTMLView *view = dynamic_cast<const KHTMLView *>(widget);
    ASSERT(view);
    return KWQ(view->part())->bridge();
}

KWQKHTMLPart *KWQKHTMLPart::partForNode(NodeImpl *node)
{
    ASSERT_ARG(node, node);
    return KWQ(node->getDocument()->view()->part());
}

NodeImpl *KWQKHTMLPart::nodeForWidget(const QWidget *widget)
{
    ASSERT_ARG(widget, widget);
    const QObject *o = widget->eventFilterObject();
    return o ? static_cast<const RenderWidget *>(o)->element() : 0;
}

void KWQKHTMLPart::setDocumentFocus(QWidget *widget)
{
    NodeImpl *node = nodeForWidget(widget);
    if (node) {
        node->getDocument()->setFocusNode(node);
    } else {
        ERROR("unable to clear focus because widget had no corresponding node");
    }
}

void KWQKHTMLPart::clearDocumentFocus(QWidget *widget)
{
    NodeImpl *node = nodeForWidget(widget);
    if (node) {
    	node->getDocument()->setFocusNode(0);
    } else {
        ERROR("unable to clear focus because widget had no corresponding node");
    }
}

void KWQKHTMLPart::saveDocumentState()
{
    // Do not save doc state if the page has a password field and a form that would be submitted
    // via https
    if (!(d->m_doc && d->m_doc->hasPasswordField() && d->m_doc->hasSecureForm())) {
        [_bridge saveDocumentState];
    }
}

void KWQKHTMLPart::restoreDocumentState()
{
    [_bridge restoreDocumentState];
}

QPtrList<KWQKHTMLPart> &KWQKHTMLPart::mutableInstances()
{
    static QPtrList<KWQKHTMLPart> instancesList;
    return instancesList;
}

void KWQKHTMLPart::updatePolicyBaseURL()
{
    // FIXME: docImpl() returns null for everything other than HTML documents; is this causing problems? -dwh
    if (parentPart() && parentPart()->docImpl()) {
        setPolicyBaseURL(parentPart()->docImpl()->policyBaseURL());
    } else {
        setPolicyBaseURL(m_url.url());
    }
}

void KWQKHTMLPart::setPolicyBaseURL(const DOMString &s)
{
    // FIXME: XML documents will cause this to return null.  docImpl() is
    // an HTMLdocument only. -dwh
    if (docImpl())
        docImpl()->setPolicyBaseURL(s);
    ConstFrameIt end = d->m_frames.end();
    for (ConstFrameIt it = d->m_frames.begin(); it != end; ++it) {
        ReadOnlyPart *subpart = (*it).m_part;
        static_cast<KWQKHTMLPart *>(subpart)->setPolicyBaseURL(s);
    }
}

QString KWQKHTMLPart::requestedURLString() const
{
    return QString::fromNSString([_bridge requestedURLString]);
}

QString KWQKHTMLPart::incomingReferrer() const
{
    return QString::fromNSString([_bridge incomingReferrer]);
}

void KWQKHTMLPart::forceLayout()
{
    KHTMLView *v = d->m_view;
    if (v) {
        v->layout();
        // We cannot unschedule a pending relayout, since the force can be called with
        // a tiny rectangle from a drawRect update.  By unscheduling we in effect
        // "validate" and stop the necessary full repaint from occurring.  Basically any basic
        // append/remove DHTML is broken by this call.  For now, I have removed the optimization
        // until we have a better invalidation stategy. -dwh
        //v->unscheduleRelayout();
    }
}

void KWQKHTMLPart::forceLayoutForPageWidth(float pageWidth)
{
    // Dumping externalRepresentation(_part->renderer()).ascii() is a good trick to see
    // the state of things before and after the layout
    RenderCanvas *root = static_cast<RenderCanvas *>(xmlDocImpl()->renderer());
    if (root) {
        // This magic is basically copied from khtmlview::print
        root->setWidth((int)ceil(pageWidth));
        root->setNeedsLayoutAndMinMaxRecalc();
        forceLayout();
    }
}

void KWQKHTMLPart::sendResizeEvent()
{
    KHTMLView *v = d->m_view;
    if (v) {
        // Sending an event can result in the destruction of the view and part.
        // We ref so that happens after we return from the KHTMLView function.
        v->ref();
	QResizeEvent e;
	v->resizeEvent(&e);
        v->deref();
    }
}

void KWQKHTMLPart::runJavaScriptAlert(const QString &message)
{
    QString text = message;
    text.replace('\\', backslashAsCurrencySymbol());
    [_bridge runJavaScriptAlertPanelWithMessage:text.getNSString()];
}

bool KWQKHTMLPart::runJavaScriptConfirm(const QString &message)
{
    QString text = message;
    text.replace('\\', backslashAsCurrencySymbol());
    return [_bridge runJavaScriptConfirmPanelWithMessage:text.getNSString()];
}

bool KWQKHTMLPart::runJavaScriptPrompt(const QString &prompt, const QString &defaultValue, QString &result)
{
    QString promptText = prompt;
    promptText.replace('\\', backslashAsCurrencySymbol());
    QString defaultValueText = defaultValue;
    defaultValueText.replace('\\', backslashAsCurrencySymbol());

    NSString *returnedText;
    bool ok = [_bridge runJavaScriptTextInputPanelWithPrompt:prompt.getNSString()
        defaultText:defaultValue.getNSString() returningText:&returnedText];
    if (ok) {
        result = QString::fromNSString(returnedText);
        result.replace(backslashAsCurrencySymbol(), '\\');
    }

    return ok;
}

void KWQKHTMLPart::createEmptyDocument()
{
    // Although it's not completely clear from the name of this function,
    // it does nothing if we already have a document, and just creates an
    // empty one if we have no document at all.
    if (!d->m_doc) {
        [_bridge loadEmptyDocumentSynchronously];
    }
}

void KWQKHTMLPart::addMetaData(const QString &key, const QString &value)
{
    d->m_job->addMetaData(key, value);
}

bool KWQKHTMLPart::keyEvent(NSEvent *event)
{
    ASSERT([event type] == NSKeyDown || [event type] == NSKeyUp);

    // Check for cases where we are too early for events -- possible unmatched key up
    // from pressing return in the location bar.
    DocumentImpl *doc = xmlDocImpl();
    if (!doc) {
        return false;
    }
    NodeImpl *node = doc->focusNode();
    if (!node) {
	return false;
    }
    
    NSEvent *oldCurrentEvent = _currentEvent;
    _currentEvent = [event retain];

    const char *characters = [[event characters] lossyCString];
    int ascii = (characters != nil && strlen(characters) == 1) ? characters[0] : 0;

    QKeyEvent qEvent([event type] == NSKeyDown ? QEvent::KeyPress : QEvent::KeyRelease,
		     [event keyCode],
		     ascii,
		     stateForCurrentEvent(),
		     QString::fromNSString([event characters]),
		     [event isARepeat]);
    bool result = node->dispatchKeyEvent(&qEvent);

    // We want to send both a down and a press for the initial key event.
    // This is a temporary hack; we need to do this a better way.
    if ([event type] == NSKeyDown && ![event isARepeat]) {
	QKeyEvent qEvent(QEvent::KeyPress,
			 [event keyCode],
			 ascii,
			 stateForCurrentEvent(),
			 QString::fromNSString([event characters]),
			 true);
        node->dispatchKeyEvent(&qEvent);
    }

    ASSERT(_currentEvent == event);
    [event release];
    _currentEvent = oldCurrentEvent;

    return result;
}

// This does the same kind of work that KHTMLPart::openURL does, except it relies on the fact
// that a higher level already checked that the URLs match and the scrolling is the right thing to do.
void KWQKHTMLPart::scrollToAnchor(const KURL &URL)
{
    cancelRedirection();

    m_url = URL;
    started(0);

    if (!gotoAnchor(URL.encodedHtmlRef()))
        gotoAnchor(URL.htmlRef());

    d->m_bComplete = true;
    d->m_doc->setParsing(false);

    completed();
}

bool KWQKHTMLPart::closeURL()
{
    saveDocumentState();
    return KHTMLPart::closeURL();
}

void KWQKHTMLPart::khtmlMousePressEvent(MousePressEvent *event)
{
    // If we got the event back, that must mean it wasn't prevented,
    // so it's allowed to start a drag or selection.
    _mouseDownMayStartDrag = true;
    _mouseDownMayStartSelect = true;

    if (!passWidgetMouseDownEventToWidget(event)) {
        // We don't do this at the start of mouse down handling (before calling into WebCore),
        // because we don't want to do it until we know we didn't hit a widget.
        NSView *view = d->m_view->getDocumentView();
        if ([_currentEvent clickCount] <= 1 && [_bridge firstResponder] != view) {
            [_bridge makeFirstResponder:view];
        }
        
        KHTMLPart::khtmlMousePressEvent(event);
    }
}

void KWQKHTMLPart::khtmlMouseDoubleClickEvent(MouseDoubleClickEvent *event)
{
    if (!passWidgetMouseDownEventToWidget(event)) {
        KHTMLPart::khtmlMouseDoubleClickEvent(event);
    }
}

bool KWQKHTMLPart::passWidgetMouseDownEventToWidget(khtml::MouseEvent *event)
{
    // Figure out which view to send the event to.
    RenderObject *target = event->innerNode().handle()->renderer();
    if (!target)
        return false;

    QWidget* widget = RenderLayer::gScrollBar;
    if (!widget) {
        if (!target->isWidget())
            return false;
        widget = static_cast<RenderWidget *>(target)->widget();
    }

    // Doubleclick events don't exist in Cocoa.  Since passWidgetMouseDownEventToWidget will
    // just pass _currentEvent down to the widget,  we don't want to call it for events that
    // don't correspond to Cocoa events.  The mousedown/ups will have already been passed on as
    // part of the pressed/released handling.
    if (!MouseDoubleClickEvent::test(event))
        return passWidgetMouseDownEventToWidget(widget);
    else
        return true;
}

bool KWQKHTMLPart::passWidgetMouseDownEventToWidget(RenderWidget *renderWidget)
{
    return passWidgetMouseDownEventToWidget(renderWidget->widget());
}

bool KWQKHTMLPart::passWidgetMouseDownEventToWidget(QWidget* widget)
{
    if (!widget) {
        ERROR("hit a RenderWidget without a corresponding QWidget, means a frame is half-constructed");
        return true;
    }
    
    NSView *nodeView = widget->getView();
    ASSERT(nodeView);
    ASSERT([nodeView superview]);
    NSView *topView = nodeView;
    NSView *superview;
    while ((superview = [topView superview])) {
        topView = superview;
    }
    NSView *view = [nodeView hitTest:[[nodeView superview] convertPoint:[_currentEvent locationInWindow] fromView:topView]];
    if (view == nil) {
        ERROR("KHTML says we hit a RenderWidget, but AppKit doesn't agree we hit the corresponding NSView");
        return true;
    }
    
    if ([_bridge firstResponder] == view) {
        // In the case where we just became first responder, we should send the mouseDown:
        // to the NSTextField, not the NSTextField's editor. This code makes sure that happens.
        // If we don't do this, we see a flash of selected text when clicking in a text field.
        if (_firstResponderAtMouseDownTime != view && [view isKindOfClass:[NSTextView class]]) {
            NSView *superview = view;
            while (superview != nodeView) {
                superview = [superview superview];
                ASSERT(superview);
                if ([superview isKindOfClass:[NSControl class]]) {
                    NSControl *control = superview;
                    if ([control currentEditor] == view) {
                        view = superview;
                    }
                    break;
                }
            }
        }
    } else {
        // Normally [NSWindow sendEvent:] handles setting the first responder.
        // But in our case, the event was sent to the view representing the entire web page.
        if ([_currentEvent clickCount] <= 1 && [view acceptsFirstResponder] && [view needsPanelToBecomeKey]) {
            [_bridge makeFirstResponder:view];
        }
    }

    ASSERT(!_sendingEventToSubview);
    _sendingEventToSubview = true;
    [view mouseDown:_currentEvent];
    _sendingEventToSubview = false;
    
    // Remember which view we sent the event to, so we can direct the release event properly.
    _mouseDownView = view;
    _mouseDownWasInSubframe = false;

    return true;
}

bool KWQKHTMLPart::lastEventIsMouseUp()
{
    // Many AK widgets run their own event loops and consume events while the mouse is down.
    // When they finish, currentEvent is the mouseUp that they exited on.  We need to update
    // the khtml state with this mouseUp, which khtml never saw.  This method lets us detect
    // that state.
    NSEvent *currentEventAfterHandlingMouseDown = [NSApp currentEvent];
    if (_currentEvent != currentEventAfterHandlingMouseDown) {
        if ([currentEventAfterHandlingMouseDown type] == NSLeftMouseUp) {
            return true;
        }
    }
    return false;
}
    
// Note that this does the same kind of check as [target isDescendantOf:superview].
// There are two differences: This is a lot slower because it has to walk the whole
// tree, and this works in cases where the target has already been deallocated.
static bool findViewInSubviews(NSView *superview, NSView *target)
{
    NSEnumerator *e = [[superview subviews] objectEnumerator];
    NSView *subview;
    while ((subview = [e nextObject])) {
        if (subview == target || findViewInSubviews(subview, target))
            return true;
    }
    return false;
}

NSView *KWQKHTMLPart::mouseDownViewIfStillGood()
{
    // Since we have no way of tracking the lifetime of _mouseDownView, we have to assume that
    // it could be deallocated already. We search for it in our subview tree; if we don't find
    // it, we set it to nil.
    NSView *mouseDownView = _mouseDownView;
    if (!mouseDownView) {
        return nil;
    }
    KHTMLView *topKHTMLView = d->m_view;
    NSView *topView = topKHTMLView ? topKHTMLView->getView() : nil;
    if (!topView || !findViewInSubviews(topView, mouseDownView)) {
        _mouseDownView = nil;
        return nil;
    }
    return mouseDownView;
}

void KWQKHTMLPart::khtmlMouseMoveEvent(MouseMoveEvent *event)
{
    if ([_currentEvent type] == NSLeftMouseDragged) {
    	NSView *view = mouseDownViewIfStillGood();

        if (view) {
            _sendingEventToSubview = true;
            [view mouseDragged:_currentEvent];
            _sendingEventToSubview = false;
            return;
        }

	if (_mouseDownMayStartDrag &&
            !d->m_selectionInitiatedWithDoubleClick &&
            !d->m_selectionInitiatedWithTripleClick &&
            [_bridge mayStartDragWithMouseDragged:_currentEvent])
        {
            // We are starting a text/image/url drag, so the cursor should be an arrow
            d->m_view->resetCursor();
            [_bridge handleMouseDragged:_currentEvent];
	    return;
	} else if (_mouseDownMayStartSelect) {
	    // we use khtml's selection but our own autoscrolling
	    [_bridge handleAutoscrollForMouseDragged:_currentEvent];
            // Don't allow dragging after we've started selecting.
            _mouseDownMayStartDrag = false;
	} else {
	    return;
	}
    } else {
	// If we allowed the other side of the bridge to handle a drag
	// last time, then m_bMousePressed might still be set. So we
	// clear it now to make sure the next move after a drag
	// doesn't look like a drag.
	d->m_bMousePressed = false;
    }

    KHTMLPart::khtmlMouseMoveEvent(event);
}

void KWQKHTMLPart::khtmlMouseReleaseEvent(MouseReleaseEvent *event)
{
    NSView *view = mouseDownViewIfStillGood();
    if (!view) {
        KHTMLPart::khtmlMouseReleaseEvent(event);
        return;
    }
    
    _sendingEventToSubview = true;
    [view mouseUp:_currentEvent];
    _sendingEventToSubview = false;
}

void KWQKHTMLPart::clearTimers(KHTMLView *view)
{
    if (view) {
        view->unscheduleRelayout();
        view->unscheduleRepaint();
    }
}

void KWQKHTMLPart::clearTimers()
{
    clearTimers(d->m_view);
}

bool KWQKHTMLPart::passSubframeEventToSubframe(NodeImpl::MouseEvent &event)
{
    switch ([_currentEvent type]) {
    	case NSLeftMouseDown: {
            NodeImpl *node = event.innerNode.handle();
            if (!node) {
                return false;
            }
            RenderPart *renderPart = dynamic_cast<RenderPart *>(node->renderer());
            if (!renderPart) {
                return false;
            }
            if (!passWidgetMouseDownEventToWidget(renderPart)) {
                return false;
            }
            _mouseDownWasInSubframe = true;
            return true;
        }
        case NSLeftMouseUp: {
            if (!_mouseDownWasInSubframe) {
                return false;
            }
            NSView *view = mouseDownViewIfStillGood();
            if (!view) {
                return false;
            }
            ASSERT(!_sendingEventToSubview);
            _sendingEventToSubview = true;
            [view mouseUp:_currentEvent];
            _sendingEventToSubview = false;
            return true;
        }
        case NSLeftMouseDragged: {
            if (!_mouseDownWasInSubframe) {
                return false;
            }
            NSView *view = mouseDownViewIfStillGood();
            if (!view) {
                return false;
            }
            ASSERT(!_sendingEventToSubview);
            _sendingEventToSubview = true;
            [view mouseDragged:_currentEvent];
            _sendingEventToSubview = false;
            return true;
        }
        default:
            return false;
    }
}

int KWQKHTMLPart::buttonForCurrentEvent()
{
    switch ([_currentEvent type]) {
    case NSLeftMouseDown:
    case NSLeftMouseUp:
        return Qt::LeftButton;
    case NSRightMouseDown:
    case NSRightMouseUp:
        return Qt::RightButton;
    case NSOtherMouseDown:
    case NSOtherMouseUp:
        return Qt::MidButton;
    default:
        return 0;
    }
}

int KWQKHTMLPart::stateForCurrentEvent()
{
    int state = buttonForCurrentEvent();
    
    unsigned modifiers = [_currentEvent modifierFlags];

    if (modifiers & NSControlKeyMask)
        state |= Qt::ControlButton;
    if (modifiers & NSShiftKeyMask)
        state |= Qt::ShiftButton;
    if (modifiers & NSAlternateKeyMask)
        state |= Qt::AltButton;
    if (modifiers & NSCommandKeyMask)
        state |= Qt::MetaButton;
    
    return state;
}

void KWQKHTMLPart::mouseDown(NSEvent *event)
{
    KHTMLView *v = d->m_view;
    if (!v || _sendingEventToSubview) {
        return;
    }

    _mouseDownView = nil;

    NSEvent *oldCurrentEvent = _currentEvent;
    _currentEvent = [event retain];
    
    NSResponder *oldFirstResponderAtMouseDownTime = _firstResponderAtMouseDownTime;
    // Unlike other places in WebCore where we get the first
    // responder, in this case we must be talking about the real first
    // responder, so we could just ask the bridge's window, instead of
    // the bridge. It's unclear which is better.
    _firstResponderAtMouseDownTime = [[_bridge firstResponder] retain];

    _mouseDownMayStartDrag = false;
    _mouseDownMayStartSelect = false;

    // Sending an event can result in the destruction of the view and part.
    // We ref so that happens after we return from the KHTMLView function.
    v->ref();
    QMouseEvent kEvent(QEvent::MouseButtonPress, QPoint([event locationInWindow]),
        buttonForCurrentEvent(), stateForCurrentEvent(), [event clickCount]);
    v->viewportMousePressEvent(&kEvent);
    v->deref();
    
    [_firstResponderAtMouseDownTime release];
    _firstResponderAtMouseDownTime = oldFirstResponderAtMouseDownTime;

    ASSERT(_currentEvent == event);
    [event release];
    _currentEvent = oldCurrentEvent;
}

void KWQKHTMLPart::mouseDragged(NSEvent *event)
{
    KHTMLView *v = d->m_view;
    if (!v || _sendingEventToSubview) {
        return;
    }

    NSEvent *oldCurrentEvent = _currentEvent;
    _currentEvent = [event retain];

    // Sending an event can result in the destruction of the view and part.
    // We ref so that happens after we return from the KHTMLView function.
    v->ref();
    QMouseEvent kEvent(QEvent::MouseMove, QPoint([event locationInWindow]), Qt::LeftButton, Qt::LeftButton);
    v->viewportMouseMoveEvent(&kEvent);
    v->deref();
    
    ASSERT(_currentEvent == event);
    [event release];
    _currentEvent = oldCurrentEvent;
}

void KWQKHTMLPart::mouseUp(NSEvent *event)
{
    KHTMLView *v = d->m_view;
    if (!v || _sendingEventToSubview) {
        return;
    }

    NSEvent *oldCurrentEvent = _currentEvent;
    _currentEvent = [event retain];

    // Sending an event can result in the destruction of the view and part.
    // We ref so that happens after we return from the KHTMLView function.
    v->ref();
    // Our behavior here is a little different that Qt. Qt always sends
    // a mouse release event, even for a double click. To correct problems
    // in khtml's DOM click event handling we do not send a release here
    // for a double click. Instead we send that event from KHTMLView's
    // viewportMouseDoubleClickEvent. Note also that the third click of
    // a triple click is treated as a single click, but the fourth is then
    // treated as another double click. Hence the "% 2" below.
    int clickCount = [event clickCount];
    if (clickCount > 0 && clickCount % 2 == 0) {
        QMouseEvent doubleClickEvent(QEvent::MouseButtonDblClick, QPoint([event locationInWindow]),
            buttonForCurrentEvent(), stateForCurrentEvent(), clickCount);
        v->viewportMouseDoubleClickEvent(&doubleClickEvent);
    } else {
        QMouseEvent releaseEvent(QEvent::MouseButtonRelease, QPoint([event locationInWindow]),
            buttonForCurrentEvent(), stateForCurrentEvent(), clickCount);
        v->viewportMouseReleaseEvent(&releaseEvent);
    }
    v->deref();
    
    ASSERT(_currentEvent == event);
    [event release];
    _currentEvent = oldCurrentEvent;
    
    _mouseDownView = nil;
}

/*
 A hack for the benefit of AK's PopUpButton, which uses the Carbon menu manager, which thus
 eats all subsequent events after it is starts its modal tracking loop.  After the interaction
 is done, this routine is used to fix things up.  We post a fake mouse up to balance the
 mouse down we started with.  In addition, we post a fake mouseMoved to get the cursor in sync
 with whatever we happen to be over after the tracking is done.
 */
void KWQKHTMLPart::doFakeMouseUpAfterWidgetTracking(NSEvent *downEvent)
{
    _sendingEventToSubview = false;
    ASSERT([downEvent type] == NSLeftMouseDown);
    NSEvent *fakeEvent = [NSEvent mouseEventWithType:NSLeftMouseUp
                                            location:[downEvent locationInWindow]
                                       modifierFlags:[downEvent modifierFlags]
                                           timestamp:[downEvent timestamp]
                                        windowNumber:[downEvent windowNumber]
                                             context:[downEvent context]
                                         eventNumber:[downEvent eventNumber]
                                          clickCount:[downEvent clickCount]
                                            pressure:[downEvent pressure]];
    mouseUp(fakeEvent);
    // FIXME:  We should really get the current modifierFlags here, but there's no way to poll
    // them in Cocoa, and because the event stream was stolen by the Carbon menu code we have
    // no up-to-date cache of them anywhere.
    fakeEvent = [NSEvent mouseEventWithType:NSMouseMoved
                                   location:[[_bridge window] convertScreenToBase:[NSEvent mouseLocation]]
                              modifierFlags:[downEvent modifierFlags]
                                  timestamp:[downEvent timestamp]
                               windowNumber:[downEvent windowNumber]
                                    context:[downEvent context]
                                eventNumber:0
                                 clickCount:0
                                   pressure:0];
    mouseMoved(fakeEvent);
}

void KWQKHTMLPart::mouseMoved(NSEvent *event)
{
    KHTMLView *v = d->m_view;
    // Reject a mouse moved if the button is down - screws up tracking during autoscroll
    // These happen because WebKit sometimes has to fake up moved events.
    if (!v || d->m_bMousePressed) {
        return;
    }
    
    NSEvent *oldCurrentEvent = _currentEvent;
    _currentEvent = [event retain];
    
    // Sending an event can result in the destruction of the view and part.
    // We ref so that happens after we return from the KHTMLView function.
    v->ref();
    QMouseEvent kEvent(QEvent::MouseMove, QPoint([event locationInWindow]), 0, stateForCurrentEvent());
    v->viewportMouseMoveEvent(&kEvent);
    v->deref();
    
    ASSERT(_currentEvent == event);
    [event release];
    _currentEvent = oldCurrentEvent;
}

bool KWQKHTMLPart::sendContextMenuEvent(NSEvent *event)
{
    DocumentImpl *doc = d->m_doc;
    KHTMLView *v = d->m_view;
    if (!doc || !v) {
        return false;
    }

    NSEvent *oldCurrentEvent = _currentEvent;
    _currentEvent = [event retain];
    
    QMouseEvent qev(QEvent::MouseButtonPress, QPoint([event locationInWindow]),
        buttonForCurrentEvent(), stateForCurrentEvent(), [event clickCount]);

    int xm, ym;
    v->viewportToContents(qev.x(), qev.y(), xm, ym);

    NodeImpl::MouseEvent mev(qev.stateAfter(), NodeImpl::MousePress);
    doc->prepareMouseEvent(false, xm, ym, &mev);

    // Sending an event can result in the destruction of the view and part.
    // We ref so that happens after we return from the KHTMLView function.
    v->ref();
    bool swallowEvent = v->dispatchMouseEvent(EventImpl::CONTEXTMENU_EVENT,
        mev.innerNode.handle(), true, 0, &qev, true, NodeImpl::MousePress);
    v->deref();

    ASSERT(_currentEvent == event);
    [event release];
    _currentEvent = oldCurrentEvent;

    return swallowEvent;
}

struct ListItemInfo {
    unsigned start;
    unsigned end;
};

static NSFileWrapper *fileWrapperForElement(ElementImpl *e)
{
    RenderImage *renderer = static_cast<RenderImage *>(e->renderer());
    NSImage *image = renderer->pixmap().image();
    NSData *tiffData = [image TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:0.0];

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:tiffData];
    [wrapper setPreferredFilename:@"image.tiff"];

    return [wrapper autorelease];
}

static ElementImpl *listParent(ElementImpl *item)
{
    // Ick!  Avoid use of item->id() which confuses ObjC++.
    unsigned short _id = Node(item).elementId();
    
    while (_id != ID_UL && _id != ID_OL) {
        item = static_cast<ElementImpl *>(item->parentNode());
        if (!item)
            break;
        _id = Node(item).elementId();
    }
    return item;
}

static NodeImpl* isTextFirstInListItem(NodeImpl *e)
{
    if (Node(e).nodeType() != Node::TEXT_NODE)
        return 0;
    NodeImpl* par = e->parentNode();
    while (par) {
        if (par->firstChild() != e)
            return 0;
        if (Node(par).elementId() == ID_LI)
            return par;
        e = par;
        par = par->parentNode();
    }
    return 0;
}

#define BULLET_CHAR 0x2022
#define SQUARE_CHAR 0x25AA
#define CIRCLE_CHAR 0x25E6

NSAttributedString *KWQKHTMLPart::attributedString(NodeImpl *_startNode, int startOffset, NodeImpl *endNode, int endOffset)
{
    if (_startNode == nil) {
        return nil;
    }
    
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];

    bool hasNewLine = true;
    bool addedSpace = true;
    bool hasParagraphBreak = true;
    const ElementImpl *linkStartNode = 0;
    unsigned linkStartLocation = 0;
    QPtrList<ElementImpl> listItems;
    QValueList<ListItemInfo> listItemLocations;
    float maxMarkerWidth = 0;
    
    Node n = _startNode;
    
    // If the first item is the entire text of a list item, use the list item node as the start of the 
    // selection, not the text node.  The user's intent was probably to select the list.
    if (n.nodeType() == Node::TEXT_NODE && startOffset == 0) {
        NodeImpl *startListNode = isTextFirstInListItem(_startNode);
        if (startListNode){
            _startNode = startListNode;
            n = _startNode;
        }
    }
    
    while (!n.isNull()) {
        RenderObject *renderer = n.handle()->renderer();
        if (renderer) {
            RenderStyle *style = renderer->style();
            NSFont *font = style->font().getNSFont();
            if (n.nodeType() == Node::TEXT_NODE) {
                if (hasNewLine) {
                    addedSpace = true;
                    hasNewLine = false;
                }
                QString text;
                QString str = n.nodeValue().string();
                int start = (n == _startNode) ? startOffset : -1;
                int end = (n == endNode) ? endOffset : -1;
                if (renderer->isText()) {
                    if (renderer->style()->whiteSpace() == PRE) {
                        int runStart = (start == -1) ? 0 : start;
                        int runEnd = (end == -1) ? str.length() : end;
                        text += str.mid(runStart, runEnd-runStart);
                        addedSpace = str[runEnd-1].direction() == QChar::DirWS;
                    }
                    else {
                        RenderText* textObj = static_cast<RenderText*>(renderer);
                        TextRunArray runs = textObj->textRuns();
                        if (runs.count() == 0 && str.length() > 0 && !addedSpace) {
                            // We have no runs, but we do have a length.  This means we must be
                            // whitespace that collapsed away at the end of a line.
                            text += " ";
                            addedSpace = true;
                        }
                        else {
                            addedSpace = false;
                            for (unsigned i = 0; i < runs.count(); i++) {
                                int runStart = (start == -1) ? runs[i]->m_start : start;
                                int runEnd = (end == -1) ? runs[i]->m_start + runs[i]->m_len : end;
                                runEnd = QMIN(runEnd, runs[i]->m_start + runs[i]->m_len);
                                bool spaceBetweenRuns = false;
                                if (runStart >= runs[i]->m_start &&
                                    runStart < runs[i]->m_start + runs[i]->m_len) {
                                    text += str.mid(runStart, runEnd - runStart);
                                    start = -1;
                                    spaceBetweenRuns = i+1 < runs.count() && runs[i+1]->m_start > runEnd;
                                    addedSpace = str[runEnd-1].direction() == QChar::DirWS;
                                }
                                if (end != -1 && runEnd >= end)
                                    break;

                                if (spaceBetweenRuns && !addedSpace) {
                                    text += " ";
                                    addedSpace = true;
                                }
                            }
                        }
                    }
                }
                
                text.replace('\\', renderer->backslashAsCurrencySymbol());
    
                if (text.length() > 0) {
                    hasParagraphBreak = false;
                    NSMutableDictionary *attrs;

                    attrs = [[NSMutableDictionary alloc] init];
                    [attrs setObject:font forKey:NSFontAttributeName];
                    if (style && style->color().isValid())
                        [attrs setObject:style->color().getNSColor() forKey:NSForegroundColorAttributeName];
                    if (style && style->backgroundColor().isValid())
                        [attrs setObject:style->backgroundColor().getNSColor() forKey:NSBackgroundColorAttributeName];

                    NSAttributedString *partialString = [[NSAttributedString alloc] initWithString:text.getNSString() attributes:attrs];
                    [attrs release];
                    [result appendAttributedString: partialString];                
                    [partialString release];
                }
            } else {
                // This is our simple HTML -> ASCII transformation:
                QString text;
                unsigned short _id = n.elementId();
                switch(_id) {
                    case ID_A:
                        // Note the start of the <a> element.  We will add the NSLinkAttributeName
                        // attribute to the attributed string when navigating to the next sibling 
                        // of this node.
                        linkStartLocation = [result length];
                        linkStartNode = static_cast<ElementImpl*>(n.handle());
                        break;

                    case ID_BR:
                        text += "\n";
                        hasNewLine = true;
                        break;
    
                    case ID_LI:
                        {
                            QString listText;
                            ElementImpl *itemParent = listParent(static_cast<ElementImpl *>(n.handle()));
                            
                            if (!hasNewLine)
                                listText += '\n';
                            hasNewLine = true;
    
                            listItems.append(static_cast<ElementImpl*>(n.handle()));
                            ListItemInfo info;
                            info.start = [result length];
                            info.end = 0;
                            listItemLocations.append (info);
                            
                            listText += '\t';
                            if (itemParent){
                                // Ick!  Avoid use of itemParent->id() which confuses ObjC++.
                                khtml::RenderListItem *listRenderer = static_cast<khtml::RenderListItem*>(renderer);

                                maxMarkerWidth = MAX([font pointSize], maxMarkerWidth);
                                switch(listRenderer->style()->listStyleType()) {
                                    case khtml::DISC:
                                        listText += ((QChar)BULLET_CHAR);
                                        break;
                                    case khtml::CIRCLE:
                                        listText += ((QChar)CIRCLE_CHAR);
                                        break;
                                    case khtml::SQUARE:
                                        listText += ((QChar)SQUARE_CHAR);
                                        break;
                                    case khtml::LNONE:
                                        break;
                                    default:
                                        QString marker = listRenderer->markerStringValue();
                                        listText += marker;
                                        // Use AppKit metrics.  Will be rendered by AppKit.
                                        float markerWidth = [font widthOfString: marker.getNSString()];
                                        maxMarkerWidth = MAX(markerWidth, maxMarkerWidth);
                                }

                                listText += ' ';
                                listText += '\t';
    
                                NSMutableDictionary *attrs;
            
                                attrs = [[NSMutableDictionary alloc] init];
                                [attrs setObject:font forKey:NSFontAttributeName];
                                if (style && style->color().isValid())
                                    [attrs setObject:style->color().getNSColor() forKey:NSForegroundColorAttributeName];
                                if (style && style->backgroundColor().isValid())
                                    [attrs setObject:style->backgroundColor().getNSColor() forKey:NSBackgroundColorAttributeName];
            
                                NSAttributedString *partialString = [[NSAttributedString alloc] initWithString:listText.getNSString() attributes:attrs];
                                [attrs release];
                                [result appendAttributedString: partialString];                
                                [partialString release];
                            }
                        }
                        break;

                    case ID_OL:
                    case ID_UL:
                        if (!hasNewLine)
                            text += "\n";
                        hasNewLine = true;
                        break;

                    case ID_TD:
                    case ID_TH:
                    case ID_HR:
                    case ID_DD:
                    case ID_DL:
                    case ID_DT:
                    case ID_PRE:
                    case ID_BLOCKQUOTE:
                    case ID_DIV:
                        if (!hasNewLine)
                            text += '\n';
                        hasNewLine = true;
                        break;
                    case ID_P:
                    case ID_TR:
                    case ID_H1:
                    case ID_H2:
                    case ID_H3:
                    case ID_H4:
                    case ID_H5:
                    case ID_H6:
                        if (!hasNewLine)
                            text += '\n';
                        if (!hasParagraphBreak) {
                            text += '\n';
                            hasParagraphBreak = true;
                        }
                        hasNewLine = true;
                        break;
                        
                    case ID_IMG:
                        NSFileWrapper *fileWrapper = fileWrapperForElement(static_cast<ElementImpl *>(n.handle()));
                        NSTextAttachment *attachment = [[NSTextAttachment alloc] initWithFileWrapper:fileWrapper];
                        NSAttributedString *iString = [NSAttributedString attributedStringWithAttachment:attachment];
                        [result appendAttributedString: iString];
                        [attachment release];
                        break;
                }
                NSAttributedString *partialString = [[NSAttributedString alloc] initWithString:text.getNSString()];
                [result appendAttributedString: partialString];
                [partialString release];
            }
        }

        if (n == endNode)
            break;

        Node next = n.firstChild();
        if (next.isNull()){
            next = n.nextSibling();
        }

        while (next.isNull() && !n.parentNode().isNull()) {
            QString text;
            n = n.parentNode();
            next = n.nextSibling();

            unsigned short _id = n.elementId();
            switch(_id) {
                case ID_A:
                    // End of a <a> element.  Create an attributed string NSLinkAttributeName attribute
                    // for the range of the link.  Note that we create the attributed string from the DOM, which
                    // will have corrected any illegally nested <a> elements.
                    if (linkStartNode && n.handle() == linkStartNode){
                        DOMString href = parseURL(linkStartNode->getAttribute(ATTR_HREF));
                        KURL kURL = KWQ(linkStartNode->getDocument()->view()->part())->completeURL(href.string());
                        
                        NSURL *URL = kURL.getNSURL();
                        [result addAttribute:NSLinkAttributeName value:URL range:NSMakeRange(linkStartLocation, [result length]-linkStartLocation)];
                        linkStartNode = 0;
                    }
                    break;
                
                case ID_OL:
                case ID_UL:
                    if (!hasNewLine)
                        text += '\n';
                    hasNewLine = true;
                    break;

                case ID_LI:
                    {
                        int i, count = listItems.count();
                        for (i = 0; i < count; i++){
                            if (listItems.at(i) == n.handle()){
                                listItemLocations[i].end = [result length];
                                break;
                            }
                        }
                    }
                    if (!hasNewLine)
                        text += '\n';
                    hasNewLine = true;
                    break;

                case ID_TD:
                case ID_TH:
                case ID_HR:
                case ID_DD:
                case ID_DL:
                case ID_DT:
                case ID_PRE:
                case ID_BLOCKQUOTE:
                case ID_DIV:
                    if (!hasNewLine)
                        text += '\n';
                    hasNewLine = true;
                    break;
                case ID_P:
                case ID_TR:
                case ID_H1:
                case ID_H2:
                case ID_H3:
                case ID_H4:
                case ID_H5:
                case ID_H6:
                    if (!hasNewLine)
                        text += '\n';
                    // An extra newline is needed at the start, not the end, of these types of tags,
                    // so don't add another here.
                    hasNewLine = true;
                    break;
            }
            
            NSAttributedString *partialString = [[NSAttributedString alloc] initWithString:text.getNSString()];
            [result appendAttributedString:partialString];
            [partialString release];
        }

        n = next;
    }
    
    // Apply paragraph styles from outside in.  This ensures that nested lists correctly
    // override their parent's paragraph style.
    {
        unsigned i, count = listItems.count();
        ElementImpl *e;
        ListItemInfo info;

#ifdef POSITION_LIST
        NodeImpl *containingBlock;
        int containingBlockX, containingBlockY;
        
        // Determine the position of the outermost containing block.  All paragraph
        // styles and tabs should be relative to this position.  So, the horizontal position of 
        // each item in the list (in the resulting attributed string) will be relative to position 
        // of the outermost containing block.
        if (count > 0){
            containingBlock = _startNode;
            while (containingBlock->renderer()->isInline()){
                containingBlock = containingBlock->parentNode();
            }
            containingBlock->renderer()->absolutePosition(containingBlockX, containingBlockY);
        }
#endif
        
        for (i = 0; i < count; i++){
            e = listItems.at(i);
            info = listItemLocations[i];
            
            if (info.end < info.start)
                info.end = [result length];
                
            RenderObject *r = e->renderer();
            RenderStyle *style = r->style();

            int rx;
            NSFont *font = style->font().getNSFont();
            float pointSize = [font pointSize];

#ifdef POSITION_LIST
            int ry;
            r->absolutePosition(rx, ry);
            rx -= containingBlockX;
            
            // Ensure that the text is indented at least enough to allow for the markers.
            rx = MAX(rx, (int)maxMarkerWidth);
#else
            rx = (int)MAX(maxMarkerWidth, pointSize);
#endif

            // The bullet text will be right aligned at the first tab marker, followed
            // by a space, followed by the list item text.  The space is arbitrarily
            // picked as pointSize*2/3.  The space on the first line of the text item
            // is established by a left aligned tab, on subsequent lines it's established
            // by the head indent.
            NSMutableParagraphStyle *mps = [[NSMutableParagraphStyle alloc] init];
            [mps setFirstLineHeadIndent: 0];
            [mps setHeadIndent: rx];
            [mps setTabStops:[NSArray arrayWithObjects:
                        [[[NSTextTab alloc] initWithType:NSRightTabStopType location:rx-(pointSize*2/3)] autorelease],
                        [[[NSTextTab alloc] initWithType:NSLeftTabStopType location:rx] autorelease],
                        nil]];
            [result addAttribute:NSParagraphStyleAttributeName value:mps range:NSMakeRange(info.start, info.end-info.start)];
            [mps release];
        }
    }

    //NSLog (@"%@", result);
    return result;
}

QRect KWQKHTMLPart::selectionRect() const
{
    if(!xmlDocImpl()){
        return QRect();
    }

    RenderCanvas *root = static_cast<RenderCanvas *>(xmlDocImpl()->renderer());
    if (!root) {
        return QRect();

    }

    return root->selectionRect();
}

KWQWindowWidget *KWQKHTMLPart::topLevelWidget()
{
    return _windowWidget;
}

int KWQKHTMLPart::selectionStartOffset() const
{
    return d->m_startOffset;
}

int KWQKHTMLPart::selectionEndOffset() const
{
    return d->m_endOffset;
}

NodeImpl *KWQKHTMLPart::selectionStart() const
{
    return d->m_selectionStart.handle();
}

NodeImpl *KWQKHTMLPart::selectionEnd() const
{
    return d->m_selectionEnd.handle();
}

void KWQKHTMLPart::setBridge(WebCoreBridge *p)
{ 
    if (_bridge != p) {
	delete _windowWidget;
    }
    _bridge = p;
    _windowWidget = new KWQWindowWidget(_bridge);
}

void KWQKHTMLPart::setMediaType(const QString &type)
{
    if (d->m_view) {
        d->m_view->setMediaType(type);
    }
}

QChar KWQKHTMLPart::backslashAsCurrencySymbol() const
{
    DocumentImpl *doc = xmlDocImpl();
    if (!doc) {
        return '\\';
    }
    Decoder *decoder = doc->decoder();
    if (!decoder) {
        return '\\';
    }
    const QTextCodec *codec = decoder->codec();
    if (!codec) {
        return '\\';
    }
    return codec->backslashAsCurrencySymbol();
}

NSColor *KWQKHTMLPart::bodyBackgroundColor(void) const
{
    HTMLDocumentImpl *doc = docImpl();
    
    if (doc){
        HTMLElementImpl *body = doc->body();
        QColor bgColor =  body->renderer()->style()->backgroundColor();
        
        if (bgColor.isValid())
            return bgColor.getNSColor();
    }
    return nil;
}

