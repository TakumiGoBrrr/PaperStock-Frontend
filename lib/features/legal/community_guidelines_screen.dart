import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// Community guidelines shown:
///  - as a gated onboarding step right after the swipe tutorial
///    (`isOnboarding: true` — the user must scroll to the bottom and tick the
///    agreement box before continuing), and
///  - as a reference page opened from a rejected post (`isOnboarding: false`).
class CommunityGuidelinesScreen extends StatefulWidget {
  const CommunityGuidelinesScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  State<CommunityGuidelinesScreen> createState() =>
      _CommunityGuidelinesScreenState();
}

class _CommunityGuidelinesScreenState
    extends State<CommunityGuidelinesScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _reachedBottom = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // If the content is short enough that there's nothing to scroll, treat it
    // as already read after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent <= 0) {
        setState(() => _reachedBottom = true);
      }
    });
  }

  void _onScroll() {
    if (_reachedBottom) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _continue() {
    if (widget.isOnboarding) {
      context.go('/feed');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canContinue =
        !widget.isOnboarding || (_reachedBottom && _agreed);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        automaticallyImplyLeading: !widget.isOnboarding,
        title: Text(
          'Community Guidelines',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'PaperStock is a home for storytelling. To keep it safe '
                        'and welcoming for everyone, all members agree to these '
                        'guidelines. Breaking them may get your post rejected or '
                        'your account restricted.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ..._guidelines.map(
                        (g) => _GuidelineTile(
                          icon: g.icon,
                          title: g.title,
                          body: g.body,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Fiction is welcome: dark themes, complex characters, '
                          'and difficult subjects all have a place here. These '
                          'rules are about how you treat real people, not about '
                          'limiting your imagination.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.isOnboarding)
              _OnboardingFooter(
                reachedBottom: _reachedBottom,
                agreed: _agreed,
                canContinue: canContinue,
                onAgreedChanged: (v) => setState(() => _agreed = v ?? false),
                onContinue: _continue,
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _continue,
                    child: const Text('Got it'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({
    required this.reachedBottom,
    required this.agreed,
    required this.canContinue,
    required this.onAgreedChanged,
    required this.onContinue,
  });

  final bool reachedBottom;
  final bool agreed;
  final bool canContinue;
  final ValueChanged<bool?> onAgreedChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!reachedBottom)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.keyboard_double_arrow_down_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Scroll to the end to continue',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: reachedBottom ? () => onAgreedChanged(!agreed) : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: agreed,
                    onChanged: reachedBottom ? onAgreedChanged : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'I have read and agree to the Community Guidelines.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: reachedBottom
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canContinue ? onContinue : null,
              child: const Text('Agree & Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidelineTile extends StatelessWidget {
  const _GuidelineTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Guideline {
  const _Guideline({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

const List<_Guideline> _guidelines = <_Guideline>[
  _Guideline(
    icon: Icons.diversity_3_outlined,
    title: 'No hate speech',
    body: 'Don\'t attack, demean, or promote hatred or violence against a '
        'person or group based on race, ethnicity, nationality, religion, '
        'caste, gender, sexual orientation, disability, or any other '
        'protected characteristic.',
  ),
  _Guideline(
    icon: Icons.person_off_outlined,
    title: 'No targeting real people',
    body: 'Don\'t name, depict, or write content that targets, defames, or '
        'harasses a specific real person or organisation. Write about '
        'characters, not real individuals.',
  ),
  _Guideline(
    icon: Icons.shield_outlined,
    title: 'No harassment or bullying',
    body: 'No threats, intimidation, stalking, or coordinated attacks. Don\'t '
        'encourage others to harass anyone, on or off PaperStock.',
  ),
  _Guideline(
    icon: Icons.lock_outline,
    title: 'No personal information',
    body: 'Never post private or identifying information about yourself or '
        'anyone else: real names tied to others, addresses, phone numbers, '
        'emails, workplaces, or financial details. No doxxing.',
  ),
  _Guideline(
    icon: Icons.no_adult_content_outlined,
    title: 'No sexually explicit content',
    body: 'Suggestive or mature themes are allowed behind a sensitive-content '
        'warning, but sexually explicit content is not permitted and will be '
        'removed.',
  ),
  _Guideline(
    icon: Icons.warning_amber_outlined,
    title: 'Mark sensitive content',
    body: 'If your story contains graphic violence, distressing topics, or '
        'strong language, mark it as sensitive so readers can choose to '
        'reveal it.',
  ),
  _Guideline(
    icon: Icons.gavel_outlined,
    title: 'No illegal or harmful content',
    body: 'Don\'t promote, glorify, or provide instructions for illegal acts, '
        'self-harm, or content that exploits or endangers minors. This is '
        'never allowed.',
  ),
  _Guideline(
    icon: Icons.verified_outlined,
    title: 'Be authentic',
    body: 'Don\'t impersonate others, spam, or post misleading content. '
        'Respect copyright: share your own work or work you\'re allowed to '
        'share.',
  ),
];
