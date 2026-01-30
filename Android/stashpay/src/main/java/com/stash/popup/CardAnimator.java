package com.stash.popup;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.view.View;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.AccelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;

/**
 * Animation utilities for card presentation.
 * Uses spring physics aligned with iOS for consistent cross-platform feel.
 */
public class CardAnimator {
    
    private CardAnimator() {} // Prevent instantiation
    
    /**
     * Callback interface for animation completion.
     */
    public interface AnimationCallback {
        void onAnimationEnd();
    }
    
    /**
     * Animates card sliding up from bottom (phone entry).
     */
    public static void animateSlideUp(View cardView, int screenHeight, AnimationCallback callback) {
        cardView.setTranslationY(screenHeight);
        cardView.animate()
                .translationY(0)
                .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
                .setInterpolator(new AccelerateDecelerateInterpolator())
                .setListener(new AnimatorListenerAdapter() {
                    @Override
                    public void onAnimationEnd(Animator animation) {
                        if (callback != null) callback.onAnimationEnd();
                    }
                })
                .start();
    }
    
    /**
     * Animates card fade-in (tablet/popup entry).
     */
    public static void animateFadeIn(View cardView, AnimationCallback callback) {
        cardView.setAlpha(0f);
        cardView.setScaleX(0.9f);
        cardView.setScaleY(0.9f);
        
        cardView.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
                .setInterpolator(new AccelerateDecelerateInterpolator())
                .setListener(new AnimatorListenerAdapter() {
                    @Override
                    public void onAnimationEnd(Animator animation) {
                        if (callback != null) callback.onAnimationEnd();
                    }
                })
                .start();
    }
    
    /**
     * Animates card sliding down to dismiss (phone).
     */
    public static void animateSlideDownDismiss(View cardView, int dismissY, View backdropView, 
                                                AnimationCallback callback) {
        // Animate backdrop fade out
        if (backdropView != null) {
            backdropView.animate()
                    .alpha(0f)
                    .setDuration(CardConstants.ANIMATION_DURATION_FAST)
                    .start();
        }
        
        // Animate card slide down
        cardView.animate()
                .translationY(dismissY)
                .setDuration(CardConstants.ANIMATION_DURATION_ENTRY)
                .setInterpolator(new AccelerateInterpolator())
                .setListener(new AnimatorListenerAdapter() {
                    @Override
                    public void onAnimationEnd(Animator animation) {
                        if (callback != null) callback.onAnimationEnd();
                    }
                })
                .start();
    }
    
    /**
     * Animates card fade-out to dismiss (tablet/popup).
     */
    public static void animateFadeOutDismiss(View cardView, View backdropView, AnimationCallback callback) {
        // Animate backdrop fade out
        if (backdropView != null) {
            backdropView.animate()
                    .alpha(0f)
                    .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
                    .start();
        }
        
        // Animate card fade out
        cardView.animate()
                .alpha(0f)
                .scaleX(0.9f)
                .scaleY(0.9f)
                .setDuration(CardConstants.ANIMATION_DURATION_POPUP)
                .setInterpolator(new AccelerateInterpolator())
                .setListener(new AnimatorListenerAdapter() {
                    @Override
                    public void onAnimationEnd(Animator animation) {
                        if (callback != null) callback.onAnimationEnd();
                    }
                })
                .start();
    }
    
    /**
     * Animates card expansion to full screen (phone only).
     */
    public static void animateExpand(View cardView, int targetHeight, int screenHeight,
                                     float targetY, SpringInterpolator springInterpolator,
                                     AnimationCallback callback) {
        int currentHeight = cardView.getLayoutParams().height;
        
        ValueAnimator heightAnimator = ValueAnimator.ofInt(currentHeight, targetHeight);
        heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_EXPAND);
        heightAnimator.setInterpolator(springInterpolator);
        
        heightAnimator.addUpdateListener(animation -> {
            int animHeight = (int) animation.getAnimatedValue();
            FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardView.getLayoutParams();
            params.height = animHeight;
            cardView.setLayoutParams(params);
        });
        
        heightAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                if (callback != null) callback.onAnimationEnd();
            }
        });
        
        // Animate translation
        cardView.animate()
                .translationY(targetY)
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(CardConstants.ANIMATION_DURATION_EXPAND)
                .setInterpolator(springInterpolator)
                .start();
        
        heightAnimator.start();
    }
    
    /**
     * Animates card collapse to original size (phone only).
     */
    public static void animateCollapse(View cardView, int targetHeight, 
                                       SpringInterpolator springInterpolator,
                                       AnimationCallback callback) {
        int currentHeight = cardView.getLayoutParams().height;
        
        ValueAnimator heightAnimator = ValueAnimator.ofInt(currentHeight, targetHeight);
        heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_COLLAPSE);
        heightAnimator.setInterpolator(springInterpolator);
        
        heightAnimator.addUpdateListener(animation -> {
            int animHeight = (int) animation.getAnimatedValue();
            FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardView.getLayoutParams();
            params.height = animHeight;
            cardView.setLayoutParams(params);
        });
        
        heightAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                if (callback != null) callback.onAnimationEnd();
            }
        });
        
        // Animate translation back to bottom
        cardView.animate()
                .translationY(0f)
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(CardConstants.ANIMATION_DURATION_COLLAPSE)
                .setInterpolator(springInterpolator)
                .start();
        
        heightAnimator.start();
    }
    
    /**
     * Animates card snapping back to current position.
     */
    public static void animateSnapBack(View cardView, int targetHeight,
                                       SpringInterpolator springInterpolator,
                                       AnimationCallback callback) {
        int currentHeight = cardView.getLayoutParams().height;
        
        if (currentHeight != targetHeight) {
            ValueAnimator heightAnimator = ValueAnimator.ofInt(currentHeight, targetHeight);
            heightAnimator.setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK);
            heightAnimator.setInterpolator(springInterpolator);
            
            heightAnimator.addUpdateListener(animation -> {
                int animHeight = (int) animation.getAnimatedValue();
                FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) cardView.getLayoutParams();
                params.height = animHeight;
                cardView.setLayoutParams(params);
            });
            
            heightAnimator.start();
        }
        
        // Animate translation and scale back
        cardView.animate()
                .translationY(0f)
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(CardConstants.ANIMATION_DURATION_SNAP_BACK)
                .setInterpolator(springInterpolator)
                .setListener(new AnimatorListenerAdapter() {
                    @Override
                    public void onAnimationEnd(Animator animation) {
                        if (callback != null) callback.onAnimationEnd();
                    }
                })
                .start();
    }
    
    /**
     * Animates backdrop opacity during drag.
     */
    public static void animateBackdropOpacity(View backdropView, float targetAlpha, int duration) {
        if (backdropView == null) return;
        
        backdropView.animate()
                .alpha(targetAlpha)
                .setDuration(duration)
                .start();
    }
}
