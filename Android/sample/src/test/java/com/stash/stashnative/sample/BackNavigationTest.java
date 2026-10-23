package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.util.ReflectionHelpers;

/** U-27: Back keeps returning to parent screens after a Back on a top-level tab. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {28, 33})
public class BackNavigationTest {
  @Test public void backReturnsToParentsAfterATopLevelBack() {
    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      MainViewModel model = ReflectionHelpers.getField(activity, "viewModel");
      // Android 12+ moves the task back here and keeps this instance; Back must still work later.
      model.navigateTo(MainViewModel.Screen.SETTINGS);
      activity.getOnBackPressedDispatcher().onBackPressed();

      model.navigateTo(MainViewModel.Screen.CARD_OPTIONS);
      activity.getOnBackPressedDispatcher().onBackPressed();
      assertEquals(MainViewModel.Screen.SETTINGS, model.getCurrentScreen());

      model.openInstanceDetails(model.getSelectedApiKey().id);
      model.navigateTo(MainViewModel.Screen.CHECKOUT_PAYLOAD);
      activity.getOnBackPressedDispatcher().onBackPressed();
      assertEquals(MainViewModel.Screen.INSTANCE_DETAILS, model.getCurrentScreen());
      activity.getOnBackPressedDispatcher().onBackPressed();
      assertEquals(MainViewModel.Screen.API, model.getCurrentScreen());
    } finally {
      controller.pause().stop().destroy();
    }
  }
}
