/*
 * Copyright (C) Canon Inc. 2016
 * Copyright (C) 2017 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "AnimationTimeline.h"

#include "Animation.h"
#include "AnimationEffectReadOnly.h"
#include "AnimationList.h"
#include "CSSAnimation.h"
#include "CSSPropertyAnimation.h"
#include "CSSTransition.h"
#include "DocumentTimeline.h"
#include "Element.h"
#include "KeyframeEffectReadOnly.h"
#include "RenderStyle.h"
#include "RenderView.h"
#include "StylePropertyShorthand.h"
#include "WebAnimationUtilities.h"
#include <wtf/text/TextStream.h>
#include <wtf/text/WTFString.h>

namespace WebCore {

AnimationTimeline::AnimationTimeline(ClassType classType)
    : m_classType(classType)
{
}

AnimationTimeline::~AnimationTimeline()
{
}

void AnimationTimeline::addAnimation(Ref<WebAnimation>&& animation)
{
    m_animationsWithoutTarget.add(animation.ptr());
    m_animations.add(WTFMove(animation));
    timingModelDidChange();
}

void AnimationTimeline::removeAnimation(Ref<WebAnimation>&& animation)
{
    m_animationsWithoutTarget.remove(animation.ptr());
    m_animations.remove(WTFMove(animation));
    timingModelDidChange();
}

std::optional<double> AnimationTimeline::bindingsCurrentTime()
{
    auto time = currentTime();
    if (!time)
        return std::nullopt;
    return secondsToWebAnimationsAPITime(*time);
}

void AnimationTimeline::setCurrentTime(Seconds currentTime)
{
    m_currentTime = currentTime;
    timingModelDidChange();
}

HashMap<Element*, ListHashSet<RefPtr<WebAnimation>>>& AnimationTimeline::relevantMapForAnimation(WebAnimation& animation)
{
    if (animation.isCSSAnimation())
        return m_elementToCSSAnimationsMap;
    if (animation.isCSSTransition())
        return m_elementToCSSTransitionsMap;
    return m_elementToAnimationsMap;
}

void AnimationTimeline::animationWasAddedToElement(WebAnimation& animation, Element& element)
{
    m_animationsWithoutTarget.remove(&animation);

    relevantMapForAnimation(animation).ensure(&element, [] {
        return ListHashSet<RefPtr<WebAnimation>> { };
    }).iterator->value.add(&animation);
}

static inline bool removeCSSTransitionFromMap(CSSTransition& transition, Element& element, HashMap<Element*, HashMap<CSSPropertyID, RefPtr<CSSTransition>>>& map)
{
    auto iterator = map.find(&element);
    if (iterator == map.end())
        return false;

    auto& cssTransitionsByProperty = iterator->value;
    cssTransitionsByProperty.remove(transition.property());
    if (cssTransitionsByProperty.isEmpty())
        map.remove(&element);
    return true;
}

void AnimationTimeline::animationWasRemovedFromElement(WebAnimation& animation, Element& element)
{
    // This animation doesn't have a target for now.
    m_animationsWithoutTarget.add(&animation);

    // First, we clear this animation from one of the m_elementToCSSAnimationsMap, m_elementToCSSTransitionsMap,
    // m_elementToAnimationsMap or m_elementToCompletedCSSTransitionByCSSPropertyID map, whichever is relevant to
    // this type of animation.
    auto& map = relevantMapForAnimation(animation);
    auto iterator = map.find(&element);
    if (iterator == map.end())
        return;

    auto& animations = iterator->value;
    animations.remove(&animation);
    if (!animations.size())
        map.remove(iterator);

    // Now, if we're dealing with a declarative animation, we remove it from either the m_elementToCSSAnimationByName
    // or the m_elementToRunningCSSTransitionByCSSPropertyID map, whichever is relevant to this type of animation.
    if (is<CSSAnimation>(animation)) {
        auto iterator = m_elementToCSSAnimationByName.find(&element);
        if (iterator != m_elementToCSSAnimationByName.end()) {
            auto& cssAnimationsByName = iterator->value;
            auto& name = downcast<CSSAnimation>(animation).animationName();
            cssAnimationsByName.remove(name);
            if (cssAnimationsByName.isEmpty())
                m_elementToCSSAnimationByName.remove(&element);
        }
    } else if (is<CSSTransition>(animation)) {
        auto& transition = downcast<CSSTransition>(animation);
        if (!removeCSSTransitionFromMap(transition, element, m_elementToRunningCSSTransitionByCSSPropertyID))
            removeCSSTransitionFromMap(transition, element, m_elementToCompletedCSSTransitionByCSSPropertyID);
    }
}

Vector<RefPtr<WebAnimation>> AnimationTimeline::animationsForElement(Element& element, Ordering ordering) const
{
    Vector<RefPtr<WebAnimation>> animations;
    if (m_elementToCSSTransitionsMap.contains(&element)) {
        const auto& cssTransitions = m_elementToCSSTransitionsMap.get(&element);
        if (ordering == Ordering::Sorted) {
            Vector<RefPtr<WebAnimation>> sortedCSSTransitions;
            sortedCSSTransitions.appendRange(cssTransitions.begin(), cssTransitions.end());
            std::sort(sortedCSSTransitions.begin(), sortedCSSTransitions.end(), [](auto& lhs, auto& rhs) {
                // Sort transitions first by their generation time, and then by transition-property.
                // https://drafts.csswg.org/css-transitions-2/#animation-composite-order
                auto* lhsTransition = downcast<CSSTransition>(lhs.get());
                auto* rhsTransition = downcast<CSSTransition>(rhs.get());
                if (lhsTransition->generationTime() != rhsTransition->generationTime())
                    return lhsTransition->generationTime() < rhsTransition->generationTime();
                return lhsTransition->transitionProperty().utf8() < rhsTransition->transitionProperty().utf8();
            });
            animations.appendVector(sortedCSSTransitions);
        } else
            animations.appendRange(cssTransitions.begin(), cssTransitions.end());
    }
    if (m_elementToCSSAnimationsMap.contains(&element)) {
        const auto& cssAnimations = m_elementToCSSAnimationsMap.get(&element);
        animations.appendRange(cssAnimations.begin(), cssAnimations.end());
    }
    if (m_elementToAnimationsMap.contains(&element)) {
        const auto& webAnimations = m_elementToAnimationsMap.get(&element);
        animations.appendRange(webAnimations.begin(), webAnimations.end());
    }
    return animations;
}

void AnimationTimeline::removeAnimationsForElement(Element& element)
{
    for (auto& animation : animationsForElement(element))
        animation->remove();
}

void AnimationTimeline::cancelDeclarativeAnimationsForElement(Element& element)
{
    for (auto& cssTransition : m_elementToCSSTransitionsMap.get(&element))
        cssTransition->cancel();
    for (auto& cssAnimation : m_elementToCSSAnimationsMap.get(&element))
        cssAnimation->cancel();
}

void AnimationTimeline::updateCSSAnimationsForElement(Element& element, const RenderStyle* currentStyle, const RenderStyle& afterChangeStyle)
{
    // In case this element is newly getting a "display: none" we need to cancel all of its animations and disregard new ones.
    if (currentStyle && currentStyle->hasAnimations() && currentStyle->display() != DisplayType::None && afterChangeStyle.display() == DisplayType::None) {
        if (m_elementToCSSAnimationByName.contains(&element)) {
            for (const auto& cssAnimationsByNameMapItem : m_elementToCSSAnimationByName.take(&element))
                cancelOrRemoveDeclarativeAnimation(cssAnimationsByNameMapItem.value);
        }
        return;
    }

    if (currentStyle && currentStyle->hasAnimations() && afterChangeStyle.hasAnimations() && *(currentStyle->animations()) == *(afterChangeStyle.animations()))
        return;

    static NeverDestroyed<const String> animationNameNone(MAKE_STATIC_STRING_IMPL("none"));

    // First, compile the list of animation names that were applied to this element up to this point.
    HashSet<String> namesOfPreviousAnimations;
    if (currentStyle && currentStyle->hasAnimations()) {
        auto* previousAnimations = currentStyle->animations();
        for (size_t i = 0; i < previousAnimations->size(); ++i) {
            auto& previousAnimation = previousAnimations->animation(i);
            if (previousAnimation.isValidAnimation() && previousAnimation.name() != animationNameNone)
                namesOfPreviousAnimations.add(previousAnimation.name());
        }
    }

    // Create or get the CSSAnimations by animation name map for this element.
    auto& cssAnimationsByName = m_elementToCSSAnimationByName.ensure(&element, [] {
        return HashMap<String, RefPtr<CSSAnimation>> { };
    }).iterator->value;

    if (auto* currentAnimations = afterChangeStyle.animations()) {
        for (size_t i = 0; i < currentAnimations->size(); ++i) {
            auto& currentAnimation = currentAnimations->animation(i);
            auto& name = currentAnimation.name();
            if (namesOfPreviousAnimations.contains(name)) {
                // We've found the name of this animation in our list of previous animations, this means we've already
                // created a CSSAnimation object for it and need to ensure that this CSSAnimation is backed by the current
                // animation object for this animation name.
                cssAnimationsByName.get(name)->setBackingAnimation(currentAnimation);
            } else if (currentAnimation.isValidAnimation() && name != animationNameNone) {
                // Otherwise we are dealing with a new animation name and must create a CSSAnimation for it.
                cssAnimationsByName.set(name, CSSAnimation::create(element, currentAnimation, currentStyle, afterChangeStyle));
            }
            // Remove the name of this animation from our list since it's now known to be current.
            namesOfPreviousAnimations.remove(name);
        }
    }

    // The animations names left in namesOfPreviousAnimations are now known to no longer apply so we need to
    // remove the CSSAnimation object created for them.
    for (const auto& nameOfAnimationToRemove : namesOfPreviousAnimations)
        cancelOrRemoveDeclarativeAnimation(cssAnimationsByName.take(nameOfAnimationToRemove));

    // Remove the map of CSSAnimations by animation name for this element if it's now empty.
    if (cssAnimationsByName.isEmpty())
        m_elementToCSSAnimationByName.remove(&element);
}

RefPtr<WebAnimation> AnimationTimeline::cssAnimationForElementAndProperty(Element& element, CSSPropertyID property)
{
    RefPtr<WebAnimation> matchingAnimation;
    for (const auto& animation : m_elementToCSSAnimationsMap.get(&element)) {
        auto* effect = animation->effect();
        if (is<KeyframeEffectReadOnly>(effect) && downcast<KeyframeEffectReadOnly>(effect)->animatedProperties().contains(property))
            matchingAnimation = animation;
    }
    return matchingAnimation;
}

static bool propertyInStyleMatchesValueForTransitionInMap(CSSPropertyID property, const RenderStyle& style, HashMap<CSSPropertyID, RefPtr<CSSTransition>>& transitions)
{
    if (auto* transition = transitions.get(property)) {
        if (CSSPropertyAnimation::propertiesEqual(property, &style, &transition->targetStyle()))
            return true;
    }
    return false;
}

static double transitionCombinedDuration(const Animation* transition)
{
    return std::max(0.0, transition->duration()) + transition->delay();
}

static bool transitionMatchesProperty(const Animation& transition, CSSPropertyID property)
{
    auto mode = transition.animationMode();
    if (mode == Animation::AnimateNone || mode == Animation::AnimateUnknownProperty)
        return false;
    if (mode == Animation::AnimateSingleProperty) {
        auto transitionProperty = transition.property();
        if (transitionProperty != property) {
            auto shorthand = shorthandForProperty(transitionProperty);
            for (size_t i = 0; i < shorthand.length(); ++i) {
                if (shorthand.properties()[i] == property)
                    return true;
            }
            return false;
        }
    }
    return true;
}

void AnimationTimeline::updateCSSTransitionsForElement(Element& element, const RenderStyle& currentStyle, const RenderStyle& afterChangeStyle)
{
    // In case this element is newly getting a "display: none" we need to cancel all of its transitions and disregard new ones.
    if (currentStyle.hasTransitions() && currentStyle.display() != DisplayType::None && afterChangeStyle.display() == DisplayType::None) {
        if (m_elementToRunningCSSTransitionByCSSPropertyID.contains(&element)) {
            for (const auto& cssTransitionsByCSSPropertyIDMapItem : m_elementToRunningCSSTransitionByCSSPropertyID.take(&element))
                cancelOrRemoveDeclarativeAnimation(cssTransitionsByCSSPropertyIDMapItem.value);
        }
        return;
    }

    // Section 3 "Starting of transitions" from the CSS Transitions Level 1 specification.
    // https://drafts.csswg.org/css-transitions-1/#starting

    auto& runningTransitionsByProperty = m_elementToRunningCSSTransitionByCSSPropertyID.ensure(&element, [] {
        return HashMap<CSSPropertyID, RefPtr<CSSTransition>> { };
    }).iterator->value;

    auto& completedTransitionsByProperty = m_elementToCompletedCSSTransitionByCSSPropertyID.ensure(&element, [] {
        return HashMap<CSSPropertyID, RefPtr<CSSTransition>> { };
    }).iterator->value;

    auto generationTime = MonotonicTime::now();

    auto numberOfProperties = CSSPropertyAnimation::getNumProperties();
    for (int propertyIndex = 0; propertyIndex < numberOfProperties; ++propertyIndex) {
        std::optional<bool> isShorthand;
        auto property = CSSPropertyAnimation::getPropertyAtIndex(propertyIndex, isShorthand);
        if (isShorthand && *isShorthand)
            continue;

        const Animation* matchingBackingAnimation = nullptr;
        if (auto* transitions = afterChangeStyle.transitions()) {
            for (size_t i = 0; i < transitions->size(); ++i) {
                auto& backingAnimation = transitions->animation(i);
                if (transitionMatchesProperty(backingAnimation, property))
                    matchingBackingAnimation = &backingAnimation;
            }
        }

        // https://drafts.csswg.org/css-transitions-1/#before-change-style
        // Define the before-change style as the computed values of all properties on the element as of the previous style change event, except with
        // any styles derived from declarative animations such as CSS Transitions, CSS Animations, and SMIL Animations updated to the current time.
        auto existingAnimation = cssAnimationForElementAndProperty(element, property);
        const auto& beforeChangeStyle = existingAnimation ? downcast<CSSAnimation>(existingAnimation.get())->unanimatedStyle() : currentStyle;

        if (!runningTransitionsByProperty.contains(property)
            && !CSSPropertyAnimation::propertiesEqual(property, &beforeChangeStyle, &afterChangeStyle)
            && CSSPropertyAnimation::canPropertyBeInterpolated(property, &beforeChangeStyle, &afterChangeStyle)
            && !propertyInStyleMatchesValueForTransitionInMap(property, afterChangeStyle, completedTransitionsByProperty)
            && matchingBackingAnimation && transitionCombinedDuration(matchingBackingAnimation) > 0) {
            // 1. If all of the following are true:
            //   - the element does not have a running transition for the property,
            //   - the before-change style is different from and can be interpolated with the after-change style for that property,
            //   - the element does not have a completed transition for the property or the end value of the completed transition is different from the after-change style for the property,
            //   - there is a matching transition-property value, and
            //   - the combined duration is greater than 0s,

            // then implementations must remove the completed transition (if present) from the set of completed transitions
            completedTransitionsByProperty.remove(property);

            // and start a transition whose:
            //   - start time is the time of the style change event plus the matching transition delay,
            //   - end time is the start time plus the matching transition duration,
            //   - start value is the value of the transitioning property in the before-change style,
            //   - end value is the value of the transitioning property in the after-change style,
            //   - reversing-adjusted start value is the same as the start value, and
            //   - reversing shortening factor is 1.
            auto delay = Seconds(matchingBackingAnimation->delay());
            auto duration = Seconds(matchingBackingAnimation->duration());
            auto& reversingAdjustedStartStyle = beforeChangeStyle;
            auto reversingShorteningFactor = 1;
            runningTransitionsByProperty.set(property, CSSTransition::create(element, property, generationTime, *matchingBackingAnimation, &beforeChangeStyle, afterChangeStyle, delay, duration, reversingAdjustedStartStyle, reversingShorteningFactor));
        } else if (completedTransitionsByProperty.contains(property) && !propertyInStyleMatchesValueForTransitionInMap(property, afterChangeStyle, completedTransitionsByProperty)) {
            // 2. Otherwise, if the element has a completed transition for the property and the end value of the completed transition is different from
            //    the after-change style for the property, then implementations must remove the completed transition from the set of completed transitions.
            completedTransitionsByProperty.remove(property);
        }

        bool hasRunningTransition = runningTransitionsByProperty.contains(property);
        if ((hasRunningTransition || completedTransitionsByProperty.contains(property)) && !matchingBackingAnimation) {
            // 3. If the element has a running transition or completed transition for the property, and there is not a matching transition-property
            //    value, then implementations must cancel the running transition or remove the completed transition from the set of completed transitions.
            if (hasRunningTransition)
                runningTransitionsByProperty.take(property)->cancel();
            else
                completedTransitionsByProperty.remove(property);
        }

        if (matchingBackingAnimation && runningTransitionsByProperty.contains(property) && !propertyInStyleMatchesValueForTransitionInMap(property, afterChangeStyle, runningTransitionsByProperty)) {
            auto previouslyRunningTransition = runningTransitionsByProperty.take(property);
            auto& previouslyRunningTransitionCurrentStyle = previouslyRunningTransition->currentStyle();
            // 4. If the element has a running transition for the property, there is a matching transition-property value, and the end value of the running
            //    transition is not equal to the value of the property in the after-change style, then:
            if (CSSPropertyAnimation::propertiesEqual(property, &previouslyRunningTransitionCurrentStyle, &afterChangeStyle) || !CSSPropertyAnimation::canPropertyBeInterpolated(property, &currentStyle, &afterChangeStyle)) {
                // 1. If the current value of the property in the running transition is equal to the value of the property in the after-change style,
                //    or if these two values cannot be interpolated, then implementations must cancel the running transition.
                previouslyRunningTransition->cancel();
            } else if (transitionCombinedDuration(matchingBackingAnimation) <= 0.0 || !CSSPropertyAnimation::canPropertyBeInterpolated(property, &previouslyRunningTransitionCurrentStyle, &afterChangeStyle)) {
                // 2. Otherwise, if the combined duration is less than or equal to 0s, or if the current value of the property in the running transition
                //    cannot be interpolated with the value of the property in the after-change style, then implementations must cancel the running transition.
                previouslyRunningTransition->cancel();
            } else if (CSSPropertyAnimation::propertiesEqual(property, &previouslyRunningTransition->reversingAdjustedStartStyle(), &afterChangeStyle)) {
                // 3. Otherwise, if the reversing-adjusted start value of the running transition is the same as the value of the property in the after-change
                //    style (see the section on reversing of transitions for why these case exists), implementations must cancel the running transition
                previouslyRunningTransition->cancel();

                // and start a new transition whose:
                //   - reversing-adjusted start value is the end value of the running transition,
                //   - reversing shortening factor is the absolute value, clamped to the range [0, 1], of the sum of:
                //       1. the output of the timing function of the old transition at the time of the style change event, times the reversing shortening factor of the old transition
                //       2. 1 minus the reversing shortening factor of the old transition.
                //   - start time is the time of the style change event plus:
                //       1. if the matching transition delay is nonnegative, the matching transition delay, or
                //       2. if the matching transition delay is negative, the product of the new transition’s reversing shortening factor and the matching transition delay,
                //   - end time is the start time plus the product of the matching transition duration and the new transition’s reversing shortening factor,
                //   - start value is the current value of the property in the running transition,
                //   - end value is the value of the property in the after-change style
                auto& reversingAdjustedStartStyle = previouslyRunningTransition->targetStyle();
                double transformedProgress = 1;
                if (auto* effect = previouslyRunningTransition->effect())
                    transformedProgress = effect->iterationProgress().value_or(transformedProgress);
                auto reversingShorteningFactor = std::max(std::min(((transformedProgress * previouslyRunningTransition->reversingShorteningFactor()) + (1 - previouslyRunningTransition->reversingShorteningFactor())), 1.0), 0.0);
                auto delay = matchingBackingAnimation->delay() < 0 ? Seconds(matchingBackingAnimation->delay()) * reversingShorteningFactor : Seconds(matchingBackingAnimation->delay());
                auto duration = Seconds(matchingBackingAnimation->duration()) * reversingShorteningFactor;
                runningTransitionsByProperty.set(property, CSSTransition::create(element, property, generationTime, *matchingBackingAnimation, &previouslyRunningTransitionCurrentStyle, afterChangeStyle, delay, duration, reversingAdjustedStartStyle, reversingShorteningFactor));
            } else {
                // 4. Otherwise, implementations must cancel the running transition
                previouslyRunningTransition->cancel();

                // and start a new transition whose:
                //   - start time is the time of the style change event plus the matching transition delay,
                //   - end time is the start time plus the matching transition duration,
                //   - start value is the current value of the property in the running transition,
                //   - end value is the value of the property in the after-change style,
                //   - reversing-adjusted start value is the same as the start value, and
                //   - reversing shortening factor is 1.
                auto delay = Seconds(matchingBackingAnimation->delay());
                auto duration = Seconds(matchingBackingAnimation->duration());
                auto& reversingAdjustedStartStyle = currentStyle;
                auto reversingShorteningFactor = 1;
                runningTransitionsByProperty.set(property, CSSTransition::create(element, property, generationTime, *matchingBackingAnimation, &previouslyRunningTransitionCurrentStyle, afterChangeStyle, delay, duration, reversingAdjustedStartStyle, reversingShorteningFactor));
            }
        }
    }

}

void AnimationTimeline::cancelOrRemoveDeclarativeAnimation(RefPtr<DeclarativeAnimation> animation)
{
    auto phase = animation->effect()->phase();
    if (phase != AnimationEffectReadOnly::Phase::Idle && phase != AnimationEffectReadOnly::Phase::After)
        animation->cancel();
    else
        removeAnimation(animation.releaseNonNull());
}

String AnimationTimeline::description()
{
    TextStream stream;
    int count = 1;
    stream << (m_classType == DocumentTimelineClass ? "DocumentTimeline" : "AnimationTimeline") << " with " << m_animations.size() << " animations:";
    stream << "\n";
    for (const auto& animation : m_animations) {
        writeIndent(stream, 1);
        stream << count << ". " << animation->description();
        stream << "\n";
        count++;
    }
    return stream.release();
}

} // namespace WebCore
