import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/spacing.dart';
import '../blocs/connection/connection_bloc.dart';
import '../blocs/connection/connection_event.dart';
import '../blocs/connection/connection_state.dart';
import '../widgets/custom_buttons.dart';
import 'share_link_screen.dart';
import 'receive_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P File Share'),
      ),
      body: BlocListener<ConnectionBloc, ConnectionStateBloc>(
        listener: (context, state) {
          if (state is ConnectionServerError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () {
                    context.read<ConnectionBloc>().add(ResetConnectionEvent());
                  },
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.p24, vertical: AppSizes.p32),
          child: Column(
            children: [
              // Server status indicator
              BlocBuilder<ConnectionBloc, ConnectionStateBloc>(
                builder: (context, state) {
                  if (state is ConnectionServerError) {
                    return Container(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 16.sp, color: Colors.red),
                          AppSpacing.gapW8,
                          Text(
                            'Signaling Server Offline',
                            style: TextStyle(color: Colors.red, fontSize: AppSizes.textSmall),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const Spacer(),
            Icon(
              Icons.cloud_upload_outlined,
              size: 100.sp,
              color: Theme.of(context).colorScheme.primary,
            ),
            AppSpacing.gapH32,
            Text(
              'Share files seamlessly',
              style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            AppSpacing.gapH16,
            Text(
              'No file size limit. Directly peer-to-peer. Fully encrypted.',
              style: TextStyle(fontSize: AppSizes.textBody, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const Spacer(flex: 2),
            CustomButton(
              text: 'Send Files',
              icon: Icons.send_rounded,
              isPrimary: true,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShareLinkScreen()),
                );
              },
            ),
            AppSpacing.gapH16,
            CustomButton(
              text: 'Receive Files',
              icon: Icons.download_rounded,
              isPrimary: false,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReceiveScreen()),
                );
              },
            ),
            AppSpacing.gapH32,
          ],
        ),
      ),
    ),
    );
  }
}
