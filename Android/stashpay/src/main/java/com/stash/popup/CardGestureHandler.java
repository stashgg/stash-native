package com.stash.popup;

import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;

/**
 * Handles drag gestures for card expand/collapse/dismiss.
 * - Phone: Supports three states (collapsed → expanded → dismissed)
 * - Tablet: Supports dismiss only (no expand/collapse)
 */
public class CardGestureHandler implements View.OnTouchListener {
    
    private static final int DRAG_THRESHOLD_PX = 10;
    
    /**
     * Callback interface for gesture events.
     */
    public interface GestureCallback {
        void onDragStart();
        void onDragMove(float deltaY, float velocity);
        void onExpand(float velocity);
        void onCollapse(float velocity);
        void onDismiss(float velocity);
        void onSnapBack(float velocity);
    }
    
    private final GestureCallback callback;
    private final boolean isTablet;
    private final int screenHeight;
    
    private CardState currentState = CardState.COLLAPSED;
    private boolean isInteractionBlocked = false;
    
    private float initialTouchY;
    private float initialTranslationY;
    private boolean isDragging = false;
    private VelocityTracker velocityTracker;
    
    public CardGestureHandler(GestureCallback callback, boolean isTablet, int screenHeight) {
        this.callback = callback;
        this.isTablet = isTablet;
        this.screenHeight = screenHeight;
    }
    
    public void setCurrentState(CardState state) {
        this.currentState = state;
    }
    
    public CardState getCurrentState() {
        return currentState;
    }
    
    public void setInteractionBlocked(boolean blocked) {
        this.isInteractionBlocked = blocked;
    }
    
    @Override
    public boolean onTouch(View v, MotionEvent event) {
        if (isInteractionBlocked) return false;
        
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                return handleActionDown(event);
                
            case MotionEvent.ACTION_MOVE:
                return handleActionMove(event, v);
                
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                return handleActionUp(event, v);
                
            default:
                return false;
        }
    }
    
    private boolean handleActionDown(MotionEvent event) {
        initialTouchY = event.getRawY();
        initialTranslationY = 0;
        isDragging = false;
        
        // Initialize velocity tracker
        if (velocityTracker == null) {
            velocityTracker = VelocityTracker.obtain();
        } else {
            velocityTracker.clear();
        }
        velocityTracker.addMovement(event);
        
        return true;
    }
    
    private boolean handleActionMove(MotionEvent event, View cardView) {
        if (velocityTracker != null) {
            velocityTracker.addMovement(event);
        }
        
        float deltaY = event.getRawY() - initialTouchY;
        
        // Check drag threshold
        if (!isDragging && Math.abs(deltaY) > DRAG_THRESHOLD_PX) {
            isDragging = true;
            initialTranslationY = cardView.getTranslationY();
            callback.onDragStart();
        }
        
        if (!isDragging) return true;
        
        // Calculate velocity
        float velocity = 0;
        if (velocityTracker != null) {
            velocityTracker.computeCurrentVelocity(1000);
            velocity = velocityTracker.getYVelocity();
        }
        
        if (isTablet) {
            // Tablet: Only allow downward drags (dismiss)
            if (deltaY > 0) {
                callback.onDragMove(deltaY, velocity);
            }
        } else {
            // Phone: Allow both directions
            callback.onDragMove(deltaY, velocity);
        }
        
        return true;
    }
    
    private boolean handleActionUp(MotionEvent event, View cardView) {
        if (!isDragging) {
            recycleVelocityTracker();
            return false;
        }
        
        // Calculate final velocity
        float velocity = 0;
        if (velocityTracker != null) {
            velocityTracker.computeCurrentVelocity(1000);
            velocity = velocityTracker.getYVelocity();
        }
        
        float deltaY = event.getRawY() - initialTouchY;
        float cardHeight = cardView.getHeight();
        
        // Determine action based on gesture
        GestureResult result = evaluateGesture(deltaY, velocity, cardHeight);
        
        switch (result) {
            case EXPAND:
                currentState = CardState.EXPANDED;
                callback.onExpand(velocity);
                break;
            case COLLAPSE:
                currentState = CardState.COLLAPSED;
                callback.onCollapse(velocity);
                break;
            case DISMISS:
                currentState = CardState.DISMISSING;
                callback.onDismiss(velocity);
                break;
            case SNAP_BACK:
                callback.onSnapBack(velocity);
                break;
        }
        
        isDragging = false;
        recycleVelocityTracker();
        return true;
    }
    
    private void recycleVelocityTracker() {
        if (velocityTracker != null) {
            velocityTracker.recycle();
            velocityTracker = null;
        }
    }
    
    private enum GestureResult {
        EXPAND, COLLAPSE, DISMISS, SNAP_BACK
    }
    
    private GestureResult evaluateGesture(float deltaY, float velocity, float cardHeight) {
        if (isTablet) {
            return evaluateTabletGesture(deltaY, velocity, cardHeight);
        } else {
            return evaluatePhoneGesture(deltaY, velocity, cardHeight);
        }
    }
    
    /**
     * Tablet: Dismiss only (no expand/collapse).
     */
    private GestureResult evaluateTabletGesture(float deltaY, float velocity, float cardHeight) {
        if (deltaY <= 0) {
            // Upward drag on tablet - snap back
            return GestureResult.SNAP_BACK;
        }
        
        float dismissThreshold = screenHeight * CardConstants.DISMISS_DISTANCE_THRESHOLD_TABLET;
        
        // Dismiss if distance or velocity threshold met
        if (deltaY > dismissThreshold || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD_TABLET) {
            return GestureResult.DISMISS;
        }
        
        return GestureResult.SNAP_BACK;
    }
    
    /**
     * Phone: Three-state system with velocity support.
     */
    private GestureResult evaluatePhoneGesture(float deltaY, float velocity, float cardHeight) {
        float expandThreshold = cardHeight * CardConstants.EXPAND_DISTANCE_THRESHOLD;
        float collapseThreshold = cardHeight * CardConstants.COLLAPSE_DISTANCE_THRESHOLD;
        float dismissThreshold = screenHeight * CardConstants.DISMISS_DISTANCE_THRESHOLD_PHONE;
        
        // Upward drag: Check for expand
        if (deltaY < -expandThreshold || velocity < CardConstants.EXPAND_VELOCITY_THRESHOLD) {
            if (currentState != CardState.EXPANDED) {
                return GestureResult.EXPAND;
            }
        }
        
        // Downward drag
        if (deltaY > 0) {
            if (currentState == CardState.EXPANDED) {
                // From expanded: Check for dismiss or collapse
                if (deltaY > dismissThreshold && velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                    return GestureResult.DISMISS;
                } else if (deltaY > collapseThreshold || velocity > CardConstants.COLLAPSE_VELOCITY_THRESHOLD) {
                    return GestureResult.COLLAPSE;
                }
            } else {
                // From collapsed: Check for dismiss
                if (deltaY > dismissThreshold || velocity > CardConstants.DISMISS_VELOCITY_THRESHOLD) {
                    return GestureResult.DISMISS;
                }
            }
        }
        
        return GestureResult.SNAP_BACK;
    }
}
