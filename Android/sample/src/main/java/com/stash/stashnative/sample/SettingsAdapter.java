package com.stash.stashnative.sample;

import android.content.Context;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.SeekBar;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.stash.stashnative.sample.databinding.ItemApiKeyBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceActionBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceInfoBinding;
import com.stash.stashnative.sample.databinding.ItemPreferencePayloadBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceSliderBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceSwitchBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceUrlBinding;
import com.stash.stashnative.sample.databinding.ItemSectionHeaderBinding;
import java.util.ArrayList;
import java.util.List;

/**
 * Adapter for the settings-style list.
 */
public class SettingsAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {

  private List<SettingsItem> items = new ArrayList<>();
  private final MainViewModel viewModel;
  private final Callbacks callbacks;

  /** Callbacks for user actions (open card, browser, modal, generate checkout). */
  public interface Callbacks {

    void onOpenCard();

    void onOpenBrowser();

    void onOpenModal();

    void onGenerateCheckout();

    void onOpenWebshop();

    void onGenerateCheckoutForBrowser();

    void onLockLandscapeChanged(boolean on);

    void onOpenWebshopForBrowser();

    void onOpenDeeplinkTest();

    void onDeleteInstance();
  }

  public SettingsAdapter(MainViewModel viewModel, Callbacks callbacks) {
    this.viewModel = viewModel;
    this.callbacks = callbacks;
  }

  public void submitList(List<SettingsItem> newItems) {
    this.items = newItems != null ? newItems : new ArrayList<>();
    notifyDataSetChanged();
  }

  @Override
  public int getItemViewType(int position) {
    return items.get(position).type;
  }

  @NonNull
  @Override
  public RecyclerView.ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
    LayoutInflater inflater = LayoutInflater.from(parent.getContext());
    switch (viewType) {
      case SettingsItem.TYPE_SECTION_HEADER:
        return new SectionHeaderVH(ItemSectionHeaderBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_URL_PREFERENCE:
        return new UrlPreferenceVH(ItemPreferenceUrlBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_ACTION_PREFERENCE:
        return new ActionPreferenceVH(ItemPreferenceActionBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_SWITCH_PREFERENCE:
        return new SwitchPreferenceVH(ItemPreferenceSwitchBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_SLIDER_PREFERENCE:
        return new SliderPreferenceVH(ItemPreferenceSliderBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_API_KEY:
        return new ApiKeyVH(ItemApiKeyBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_INFO_PREFERENCE:
        return new InfoPreferenceVH(ItemPreferenceInfoBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_PAYLOAD_EDITOR:
        return new PayloadEditorVH(ItemPreferencePayloadBinding.inflate(inflater, parent, false));
      default:
        throw new IllegalArgumentException("Unknown type " + viewType);
    }
  }

  @Override
  public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position) {
    SettingsItem item = items.get(position);
    switch (item.type) {
      case SettingsItem.TYPE_SECTION_HEADER:
        ((SectionHeaderVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_URL_PREFERENCE:
        ((UrlPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_ACTION_PREFERENCE:
        ((ActionPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_SWITCH_PREFERENCE:
        ((SwitchPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_SLIDER_PREFERENCE:
        ((SliderPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_API_KEY:
        ((ApiKeyVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_INFO_PREFERENCE:
        ((InfoPreferenceVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_PAYLOAD_EDITOR:
        ((PayloadEditorVH) holder).bind(item);
        break;
      default:
        break;
    }
    applyCardStyle(holder.itemView, item);
    configureRowInteraction(holder, item);
  }

  /** URL rows stay non-clickable so the text field receives focus; action rows use card ripple. */
  private void configureRowInteraction(RecyclerView.ViewHolder holder, SettingsItem item) {
    View v = holder.itemView;
    switch (item.type) {
      case SettingsItem.TYPE_URL_PREFERENCE:
      case SettingsItem.TYPE_PAYLOAD_EDITOR:
        v.setClickable(false);
        v.setFocusable(false);
        break;
      case SettingsItem.TYPE_ACTION_PREFERENCE:
      case SettingsItem.TYPE_API_KEY:
        v.setClickable(true);
        v.setFocusable(true);
        break;
      default:
        v.setClickable(false);
        v.setFocusable(false);
        break;
    }
  }

  private static final int CARD_MARGIN_HORIZONTAL_DP = 16;
  private static final int CARD_MARGIN_TOP_DP = 12;
  private static final int CARD_MARGIN_BOTTOM_DP = 12;

  private void applyCardStyle(View itemView, SettingsItem item) {
    Context ctx = itemView.getContext();
    float density = ctx.getResources().getDisplayMetrics().density;
    int horizontal = Math.round(CARD_MARGIN_HORIZONTAL_DP * density);
    int top = Math.round(CARD_MARGIN_TOP_DP * density);
    int bottom = Math.round(CARD_MARGIN_BOTTOM_DP * density);

    boolean first = item.firstInCard;
    boolean last = item.lastInCard;

    if (first && last) {
      itemView.setBackgroundResource(R.drawable.bg_card_single);
      setMargins(itemView, horizontal, top, horizontal, bottom);
    } else if (first) {
      itemView.setBackgroundResource(R.drawable.bg_card_top);
      setMargins(itemView, horizontal, top, horizontal, 0);
    } else if (last) {
      itemView.setBackgroundResource(R.drawable.bg_card_bottom);
      setMargins(itemView, horizontal, 0, horizontal, bottom);
    } else {
      itemView.setBackgroundResource(R.drawable.bg_card_middle);
      setMargins(itemView, horizontal, 0, horizontal, 0);
    }
  }

  private static int themeColor(Context ctx, int attr) {
    android.util.TypedValue tv = new android.util.TypedValue();
    ctx.getTheme().resolveAttribute(attr, tv, true);
    return tv.data;
  }

  private void setMargins(View view, int left, int top, int right, int bottom) {
    ViewGroup.MarginLayoutParams lp = (ViewGroup.MarginLayoutParams) view.getLayoutParams();
    if (lp != null) {
      lp.leftMargin = left;
      lp.topMargin = top;
      lp.rightMargin = right;
      lp.bottomMargin = bottom;
      view.setLayoutParams(lp);
    }
  }

  @Override
  public int getItemCount() {
    return items.size();
  }


  static class SectionHeaderVH extends RecyclerView.ViewHolder {
    private final ItemSectionHeaderBinding binding;

    SectionHeaderVH(ItemSectionHeaderBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.sectionHeaderText.setText(item.titleRes);
    }
  }


  class UrlPreferenceVH extends RecyclerView.ViewHolder {
    private final ItemPreferenceUrlBinding binding;
    private int boundPosition = -1;

    UrlPreferenceVH(ItemPreferenceUrlBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    private int boundTitleRes;

    void bind(SettingsItem item, int position) {
      boundPosition = position;
      boundTitleRes = item.titleRes;
      binding.preferenceIcon.setImageResource(item.iconRes);
      binding.urlInputLayout.setHint(item.titleRes);
      // setInputType resets the KeyListener and clobbers selection, so set it before setText.
      int t = item.titleRes;
      boolean isUrl = t == R.string.hint_checkout_url
          || t == R.string.hint_browser_url
          || t == R.string.hint_modal_url;
      int inputType;
      if (isUrl) {
        inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI;
      } else if (t == R.string.instance_name) {
        inputType = InputType.TYPE_CLASS_TEXT;
      } else {
        // Hex colors, app ID, ingress secret: plain text, no autosuggest/autocaps.
        inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
      }
      binding.urlEditText.setInputType(inputType);
      binding.urlEditText.removeTextChangedListener(watcher);
      // Only write when the text actually differs; an unconditional setText on every rebind
      // resets the caret to index 0 and restarts the IME while the field still has focus.
      String current = binding.urlEditText.getText() != null
          ? binding.urlEditText.getText().toString() : "";
      if (!current.equals(item.value)) {
        binding.urlEditText.setText(item.value);
      }
      binding.urlEditText.addTextChangedListener(watcher);
      // Card/Modal/Browser URL rows carry an inline Open button.
      int titleRes = item.titleRes;
      boolean hasOpen = titleRes == R.string.hint_checkout_url
          || titleRes == R.string.hint_modal_url
          || titleRes == R.string.hint_browser_url;
      binding.urlOpenButton.setVisibility(hasOpen ? View.VISIBLE : View.GONE);
      // Stable ids for UI tests; rows are recycled, so null out non-open rows.
      String tag = null;
      if (titleRes == R.string.hint_checkout_url) {
        tag = "card";
      } else if (titleRes == R.string.hint_modal_url) {
        tag = "modal";
      } else if (titleRes == R.string.hint_browser_url) {
        tag = "browser";
      }
      binding.urlEditText.setContentDescription(tag == null ? null : tag + "-url-field");
      binding.urlOpenButton.setContentDescription(tag == null ? null : tag + "-open-button");
      binding.urlOpenButton.setOnClickListener(v -> {
        if (titleRes == R.string.hint_checkout_url) {
          callbacks.onOpenCard();
        } else if (titleRes == R.string.hint_modal_url) {
          callbacks.onOpenModal();
        } else if (titleRes == R.string.hint_browser_url) {
          callbacks.onOpenBrowser();
        }
      });
    }

    private final TextWatcher watcher = new TextWatcher() {
      @Override
      public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

      @Override
      public void onTextChanged(CharSequence s, int start, int before, int count) {}

      @Override
      public void afterTextChanged(Editable s) {
        String text = s != null ? s.toString() : "";
        if (boundTitleRes == R.string.hint_checkout_url) {
          viewModel.setCheckoutUrl(text);
        } else if (boundTitleRes == R.string.hint_browser_url) {
          viewModel.setBrowserUrl(text);
        } else if (boundTitleRes == R.string.hint_modal_url) {
          viewModel.setModalUrl(text);
        } else if (boundTitleRes == R.string.hint_card_background_color) {
          viewModel.setCardBackgroundColorHex(text);
        } else if (boundTitleRes == R.string.hint_modal_background_color) {
          viewModel.setModalBackgroundColorHex(text);
        } else if (boundTitleRes == R.string.instance_name) {
          viewModel.setEditingName(text);
        } else if (boundTitleRes == R.string.instance_app_id) {
          viewModel.setEditingAppId(text);
        } else if (boundTitleRes == R.string.instance_secret) {
          viewModel.setEditingSecret(text);
        }
      }
    };
  }

  class ActionPreferenceVH extends RecyclerView.ViewHolder {
    private final ItemPreferenceActionBinding binding;

    ActionPreferenceVH(ItemPreferenceActionBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item, int position) {
      binding.actionTitle.setText(item.titleRes);
      // The destructive delete row is red; every other action row uses the primary colour.
      boolean isDelete = item.titleRes == R.string.nav_delete_instance;
      binding.actionTitle.setTextColor(themeColor(binding.actionTitle.getContext(),
          isDelete ? com.google.android.material.R.attr.colorError
              : com.google.android.material.R.attr.colorPrimary));
      // Navigation rows carry a chevron; action buttons are text-only.
      boolean isNav = item.titleRes == R.string.nav_card_options
          || item.titleRes == R.string.nav_modal_options
          || item.titleRes == R.string.nav_checkout_payload
          || item.titleRes == R.string.nav_webshop_payload;
      binding.actionChevron.setVisibility(isNav ? View.VISIBLE : View.GONE);
      binding.actionRow.setOnClickListener(v -> {
        if (item.titleRes == R.string.nav_card_options) {
          viewModel.navigateTo(MainViewModel.Screen.CARD_OPTIONS);
        } else if (item.titleRes == R.string.nav_modal_options) {
          viewModel.navigateTo(MainViewModel.Screen.MODAL_OPTIONS);
        } else if (item.titleRes == R.string.nav_checkout_payload) {
          viewModel.navigateTo(MainViewModel.Screen.CHECKOUT_PAYLOAD);
        } else if (item.titleRes == R.string.nav_webshop_payload) {
          viewModel.navigateTo(MainViewModel.Screen.WEBSHOP_PAYLOAD);
        } else if (item.titleRes == R.string.generate_checkout) {
          callbacks.onGenerateCheckout();
        } else if (item.titleRes == R.string.open_webshop) {
          callbacks.onOpenWebshop();
        } else if (item.titleRes == R.string.generate_checkout_for_browser) {
          callbacks.onGenerateCheckoutForBrowser();
        } else if (item.titleRes == R.string.open_webshop_for_browser) {
          callbacks.onOpenWebshopForBrowser();
        } else if (item.titleRes == R.string.open_deeplink_test) {
          callbacks.onOpenDeeplinkTest();
        } else if (item.titleRes == R.string.nav_delete_instance) {
          callbacks.onDeleteInstance();
        }
      });
    }
  }

  class SwitchPreferenceVH extends RecyclerView.ViewHolder {
    private final ItemPreferenceSwitchBinding binding;

    SwitchPreferenceVH(ItemPreferenceSwitchBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item, int position) {
      binding.switchTitle.setText(item.titleRes);
      if (item.supportingRes != 0) {
        binding.switchSupporting.setText(item.supportingRes);
        binding.switchSupporting.setVisibility(View.VISIBLE);
      } else {
        binding.switchSupporting.setVisibility(View.GONE);
      }
      binding.switchPreference.setOnCheckedChangeListener(null);
      binding.switchPreference.setChecked(item.checked);
      binding.switchPreference.setOnCheckedChangeListener((buttonView, isChecked) -> {
        if (item.titleRes == R.string.option_force_portrait_on_checkout) {
          viewModel.setForcePortraitOnCheckout(isChecked);
        } else if (item.titleRes == R.string.option_allow_dismiss) {
          viewModel.setModalAllowDismiss(isChecked);
        } else if (item.titleRes == R.string.option_card_auto_close) {
          viewModel.setCardAutoClose(isChecked);
        } else if (item.titleRes == R.string.option_modal_auto_close) {
          viewModel.setModalAutoClose(isChecked);
        } else if (item.titleRes == R.string.option_keep_alive) {
          viewModel.setKeepAliveEnabled(isChecked);
        } else if (item.titleRes == R.string.option_lock_landscape) {
          callbacks.onLockLandscapeChanged(isChecked);
        } else if (item.titleRes == R.string.instance_production) {
          viewModel.setEditingProduction(isChecked);
        }
      });
    }
  }

  class SliderPreferenceVH extends RecyclerView.ViewHolder {
    private final ItemPreferenceSliderBinding binding;

    SliderPreferenceVH(ItemPreferenceSliderBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item, int position) {
      binding.sliderTitle.setText(item.titleRes);
      binding.sliderValue.setText(item.value);
      binding.sliderSeekBar.setProgress(item.progress);
      binding.sliderSeekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
        @Override
        public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
          if (!fromUser) {
            return;
          }
          int titleRes = item.titleRes;
          if (titleRes == R.string.phone_card_height) {
            viewModel.setPhoneCardHeight(progress);
          } else if (titleRes == R.string.checkout_phone_landscape_width) {
            viewModel.setCheckoutPhoneLandscapeWidth(progress);
          } else if (titleRes == R.string.checkout_phone_landscape_height) {
            viewModel.setCheckoutPhoneLandscapeHeight(progress);
          } else if (titleRes == R.string.tablet_portrait_width) {
            viewModel.setCheckoutTabletPortraitWidth(progress);
          } else if (titleRes == R.string.tablet_portrait_height) {
            viewModel.setCheckoutTabletPortraitHeight(progress);
          } else if (titleRes == R.string.tablet_landscape_width) {
            viewModel.setCheckoutTabletLandscapeWidth(progress);
          } else if (titleRes == R.string.tablet_landscape_height) {
            viewModel.setCheckoutTabletLandscapeHeight(progress);
          } else if (titleRes == R.string.phone_portrait_width) {
            viewModel.setModalPhonePortraitWidth(progress);
          } else if (titleRes == R.string.phone_portrait_height) {
            viewModel.setModalPhonePortraitHeight(progress);
          } else if (titleRes == R.string.phone_landscape_width) {
            viewModel.setModalPhoneLandscapeWidth(progress);
          } else if (titleRes == R.string.phone_landscape_height) {
            viewModel.setModalPhoneLandscapeHeight(progress);
          } else if (titleRes == R.string.tablet_portrait_width_modal) {
            viewModel.setModalTabletPortraitWidth(progress);
          } else if (titleRes == R.string.tablet_portrait_height_modal) {
            viewModel.setModalTabletPortraitHeight(progress);
          } else if (titleRes == R.string.tablet_landscape_width_modal) {
            viewModel.setModalTabletLandscapeWidth(progress);
          } else if (titleRes == R.string.tablet_landscape_height_modal) {
            viewModel.setModalTabletLandscapeHeight(progress);
          }
        }

        @Override
        public void onStartTrackingTouch(SeekBar seekBar) {}

        @Override
        public void onStopTrackingTouch(SeekBar seekBar) {}
      });
    }
  }

  /** Free-form JSON editor. Keystrokes update the draft only -- refreshing the list here would
   * rebind the field and fight the cursor. */
  class PayloadEditorVH extends RecyclerView.ViewHolder {
    private final ItemPreferencePayloadBinding binding;

    PayloadEditorVH(ItemPreferencePayloadBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.payloadEditText.removeTextChangedListener(watcher);
      if (!binding.payloadEditText.getText().toString().equals(item.value)) {
        binding.payloadEditText.setText(item.value);
      }
      binding.payloadEditText.addTextChangedListener(watcher);
    }

    private final TextWatcher watcher = new TextWatcher() {
      @Override
      public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

      @Override
      public void onTextChanged(CharSequence s, int start, int before, int count) {}

      @Override
      public void afterTextChanged(Editable s) {
        viewModel.setPayloadDraft(s != null ? s.toString() : "");
      }
    };
  }

  static class InfoPreferenceVH extends RecyclerView.ViewHolder {
    private final ItemPreferenceInfoBinding binding;

    InfoPreferenceVH(ItemPreferenceInfoBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.infoTitle.setText(item.titleRes);
      binding.infoValue.setText(item.value);
    }
  }

  class ApiKeyVH extends RecyclerView.ViewHolder {
    private final ItemApiKeyBinding binding;

    ApiKeyVH(ItemApiKeyBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.apiKeyName.setText(item.name);
      binding.apiKeyMode.setText(
          item.production ? R.string.api_key_production : R.string.api_key_test);
      // Leading radio selects the active instance; tapping the row opens its details.
      binding.apiKeySelected.setImageResource(
          item.checked ? R.drawable.ic_radio_selected_24 : R.drawable.ic_radio_unselected_24);
      binding.apiKeySelected.setOnClickListener(v -> viewModel.selectApiKey(item.stringId));
      binding.apiKeyRow.setOnClickListener(v -> viewModel.openInstanceDetails(item.stringId));
    }
  }
}
