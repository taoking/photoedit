import SwiftUI

struct LightPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                EditorSliderRow("曝光", value: light(\.exposure), range: -5...5, suffix: " EV", fractionDigits: 1, model: model)
                EditorSliderRow("对比度", value: light(\.contrast), range: -100...100, model: model)
                EditorSliderRow("高光", value: light(\.highlights), range: -100...100, model: model)
                EditorSliderRow("阴影", value: light(\.shadows), range: -100...100, model: model)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func light(_ keyPath: WritableKeyPath<LightAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.light[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.light[keyPath: keyPath] = value }
        })
    }
}

struct ColorPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                EditorSliderRow("色温", value: color(\.temperature), range: -100...100, model: model)
                EditorSliderRow("色调", value: color(\.tint), range: -100...100, model: model)
                EditorSliderRow("饱和度", value: color(\.saturation), range: -100...100, model: model)
                EditorSliderRow("自然饱和度", value: color(\.vibrance), range: -100...100, model: model)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func color(_ keyPath: WritableKeyPath<ColorAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.color[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.color[keyPath: keyPath] = value }
        })
    }
}

struct DetailPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                EditorSliderRow("锐化", value: detail(\.sharpness), range: 0...100, model: model)
                EditorSliderRow("暗角", value: effects(\.vignette), range: -100...100, model: model)
                HistogramView(histogram: model.histogram)
                    .frame(height: 46)
                    .accessibilityLabel("RGB 和亮度直方图")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func detail(_ keyPath: WritableKeyPath<DetailAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.detail[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.detail[keyPath: keyPath] = value }
        })
    }

    private func effects(_ keyPath: WritableKeyPath<EffectAdjustments, Double>) -> Binding<Double> {
        Binding(get: { model.state.effects[keyPath: keyPath] }, set: { value in
            model.updateContinuous { $0.effects[keyPath: keyPath] = value }
        })
    }
}

struct EditorSliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let suffix: String
    let fractionDigits: Int
    @ObservedObject var model: EditorViewModel

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = "",
        fractionDigits: Int = 0,
        model: EditorViewModel
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.suffix = suffix
        self.fractionDigits = fractionDigits
        self.model = model
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(displayValue)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }
            Slider(value: value, in: range, onEditingChanged: { editing in
                if editing { model.beginContinuousEdit() } else { model.endContinuousEdit() }
            })
        }
        .accessibilityElement(children: .combine)
    }

    private var displayValue: String {
        let raw = value.wrappedValue
        let sign = raw > 0 ? "+" : ""
        return "\(sign)\(raw.formatted(.number.precision(.fractionLength(fractionDigits))))\(suffix)"
    }
}
