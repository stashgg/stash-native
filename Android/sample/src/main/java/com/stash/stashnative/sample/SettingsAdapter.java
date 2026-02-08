package com.stash.stashnative.sample;

import android.content.Context;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.SeekBar;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.textfield.TextInputEditText;
import com.stash.stashnative.sample.databinding.ItemExpandableHeaderBinding;
import com.stash.stashnative.sample.databinding.ItemHeaderBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceActionBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceSliderBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceSwitchBinding;
import com.stash.stashnative.sample.databinding.ItemPreferenceUrlBinding;
import com.stash.stashnative.sample.databinding.ItemSectionFooterBinding;
import com.stash.stashnative.sample.databinding.ItemSectionHeaderBinding;
import java.util.ArrayList;
import java.util.List;

/**
 * RecyclerView adapter for the settings-style list (Google Settings pattern).
 * Uses ViewBinding and multiple view types.
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
      case SettingsItem.TYPE_HEADER:
        return new HeaderVH(ItemHeaderBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_SECTION_HEADER:
        return new SectionHeaderVH(ItemSectionHeaderBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_SECTION_FOOTER:
        return new SectionFooterVH(ItemSectionFooterBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_URL_PREFERENCE:
        return new UrlPreferenceVH(ItemPreferenceUrlBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_ACTION_PREFERENCE:
        return new ActionPreferenceVH(ItemPreferenceActionBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_EXPANDABLE_HEADER:
        return new ExpandableHeaderVH(ItemExpandableHeaderBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_SWITCH_PREFERENCE:
        return new SwitchPreferenceVH(ItemPreferenceSwitchBinding.inflate(inflater, parent, false));
      case SettingsItem.TYPE_SLIDER_PREFERENCE:
        return new SliderPreferenceVH(ItemPreferenceSliderBinding.inflate(inflater, parent, false));
      default:
        throw new IllegalArgumentException("Unknown type " + viewType);
    }
  }

  @Override
  public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position) {
    SettingsItem item = items.get(position);
    switch (item.type) {
      case SettingsItem.TYPE_HEADER:
        ((HeaderVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_SECTION_HEADER:
        ((SectionHeaderVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_SECTION_FOOTER:
        ((SectionFooterVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_URL_PREFERENCE:
        ((UrlPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_ACTION_PREFERENCE:
        ((ActionPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_EXPANDABLE_HEADER:
        ((ExpandableHeaderVH) holder).bind(item);
        break;
      case SettingsItem.TYPE_SWITCH_PREFERENCE:
        ((SwitchPreferenceVH) holder).bind(item, position);
        break;
      case SettingsItem.TYPE_SLIDER_PREFERENCE:
        ((SliderPreferenceVH) holder).bind(item, position);
        break;
      default:
        break;
    }
    applyCardStyle(holder.itemView, item);
  }

  private static final int CARD_MARGIN_HORIZONTAL_DP = 16;
  private static final int CARD_MARGIN_TOP_DP = 12;
  private static final int CARD_MARGIN_BOTTOM_DP = 12;

  private void applyCardStyle(View itemView, SettingsItem item) {
    if (item.type == SettingsItem.TYPE_HEADER) {
      itemView.setBackground(null);
      return;
    }
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

  private int findActionPosition(int position) {
    for (int i = 0; i < position; i++) {
      SettingsItem it = items.get(i);
      if (it.type == SettingsItem.TYPE_ACTION_PREFERENCE) {
        int titleRes = it.titleRes;
        if (titleRes == R.string.open_card) {
          return 0;
        }
        if (titleRes == R.string.open_browser) {
          return 1;
        }
        if (titleRes == R.string.open_modal) {
          return 2;
        }
        if (titleRes == R.string.generate_checkout) {
          return 3;
        }
      }
    }
    return -1;
  }

  private int findSwitchOrSliderPosition(int position) {
    int switchIndex = 0;
    for (int i = 0; i < position; i++) {
      SettingsItem it = items.get(i);
      if (it.type == SettingsItem.TYPE_SWITCH_PREFERENCE
          || it.type == SettingsItem.TYPE_SLIDER_PREFERENCE) {
        switchIndex++;
      }
    }
    return switchIndex;
  }

  static class HeaderVH extends RecyclerView.ViewHolder {
    private final ItemHeaderBinding binding;

    HeaderVH(ItemHeaderBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.headerTitle.setText(item.titleRes);
      binding.headerSubtitle.setText(item.supportingRes);
    }
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

  static class SectionFooterVH extends RecyclerView.ViewHolder {
    private final ItemSectionFooterBinding binding;

    SectionFooterVH(ItemSectionFooterBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.sectionFooterText.setText(item.titleRes);
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
      binding.urlEditText.removeTextChangedListener(watcher);
      binding.urlEditText.setText(item.value);
      binding.urlEditText.addTextChangedListener(watcher);
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
        } else if (boundTitleRes == R.string.hint_api_key) {
          viewModel.setStashApiKey(text);
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
      binding.actionIcon.setImageResource(item.iconRes);
      binding.actionTitle.setText(item.titleRes);
      binding.actionRow.setOnClickListener(v -> {
        if (item.titleRes == R.string.open_card) {
          callbacks.onOpenCard();
        } else if (item.titleRes == R.string.open_browser) {
          callbacks.onOpenBrowser();
        } else if (item.titleRes == R.string.open_modal) {
          callbacks.onOpenModal();
        } else if (item.titleRes == R.string.generate_checkout) {
          callbacks.onGenerateCheckout();
        }
      });
    }
  }

  class ExpandableHeaderVH extends RecyclerView.ViewHolder {
    private final ItemExpandableHeaderBinding binding;

    ExpandableHeaderVH(ItemExpandableHeaderBinding binding) {
      super(binding.getRoot());
      this.binding = binding;
    }

    void bind(SettingsItem item) {
      binding.expandableIcon.setImageResource(item.iconRes);
      binding.expandableTitle.setText(item.titleRes);
      binding.expandableChevron.setRotation(item.expanded ? 90f : 0f);
      binding.expandableRow.setOnClickListener(v -> {
        v.post(() -> {
          if (item.titleRes == R.string.show_checkout_options
              || item.titleRes == R.string.hide_checkout_options) {
            viewModel.toggleCheckoutOptions();
          } else if (item.titleRes == R.string.show_modal_options
              || item.titleRes == R.string.hide_modal_options) {
            viewModel.toggleModalOptions();
          }
        });
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
        } else if (item.titleRes == R.string.option_show_drag_bar) {
          viewModel.setModalShowDragBar(isChecked);
        } else if (item.titleRes == R.string.option_allow_dismiss) {
          viewModel.setModalAllowDismiss(isChecked);
        } else if (item.titleRes == R.string.option_use_test_api) {
          viewModel.setUseTestApi(isChecked);
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
}
