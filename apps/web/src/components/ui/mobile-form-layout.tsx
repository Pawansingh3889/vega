import * as React from "react"
import { cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"

interface MobileFormLayoutProps {
  children: React.ReactNode
  className?: string
  maxWidth?: 'sm' | 'md' | 'lg' | 'xl' | '2xl' | 'full'
}

const MobileFormLayout = React.forwardRef<
  HTMLDivElement,
  MobileFormLayoutProps
>(({ children, className, maxWidth = 'lg', ...props }, ref) => {
  const isMobile = useIsMobile()
  
  const maxWidthClasses = {
    sm: 'max-w-sm',
    md: 'max-w-md', 
    lg: 'max-w-lg',
    xl: 'max-w-xl',
    '2xl': 'max-w-2xl',
    full: 'max-w-full'
  }
  
  return (
    <div
      ref={ref}
      className={cn(
        "w-full mx-auto",
        isMobile 
          ? "max-w-[95vw] px-4 py-2" 
          : `${maxWidthClasses[maxWidth]} px-6 py-4`,
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
})
MobileFormLayout.displayName = "MobileFormLayout"

interface MobileFormSectionProps {
  children: React.ReactNode
  className?: string
  title?: string
  description?: string
}

const MobileFormSection = React.forwardRef<
  HTMLDivElement,
  MobileFormSectionProps
>(({ children, className, title, description, ...props }, ref) => {
  const isMobile = useIsMobile()
  
  return (
    <div
      ref={ref}
      className={cn("space-y-4", className)}
      {...props}
    >
      {(title || description) && (
        <div className={cn("space-y-1", isMobile && "px-1")}>
          {title && (
            <h3 className={cn(
              "font-medium leading-none",
              isMobile ? "text-base" : "text-lg"
            )}>
              {title}
            </h3>
          )}
          {description && (
            <p className={cn(
              "text-muted-foreground",
              isMobile ? "text-sm" : "text-sm"
            )}>
              {description}
            </p>
          )}
        </div>
      )}
      {children}
    </div>
  )
})
MobileFormSection.displayName = "MobileFormSection"

interface MobileFormGridProps {
  children: React.ReactNode
  className?: string
  columns?: 1 | 2 | 3 | 4
  mobileColumns?: 1 | 2
}

const MobileFormGrid = React.forwardRef<
  HTMLDivElement,
  MobileFormGridProps
>(({ children, className, columns = 2, mobileColumns = 1, ...props }, ref) => {
  const isMobile = useIsMobile()
  
  const getGridClass = () => {
    if (isMobile) {
      return mobileColumns === 2 ? 'grid-cols-2' : 'grid-cols-1'
    }
    
    switch (columns) {
      case 1: return 'grid-cols-1'
      case 2: return 'md:grid-cols-2'
      case 3: return 'md:grid-cols-2 lg:grid-cols-3'
      case 4: return 'md:grid-cols-2 lg:grid-cols-4'
      default: return 'md:grid-cols-2'
    }
  }
  
  return (
    <div
      ref={ref}
      className={cn(
        "grid gap-4",
        isMobile ? `grid-cols-${mobileColumns}` : getGridClass(),
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
})
MobileFormGrid.displayName = "MobileFormGrid"

interface MobileFormActionsProps {
  children: React.ReactNode
  className?: string
  align?: 'left' | 'center' | 'right'
}

const MobileFormActions = React.forwardRef<
  HTMLDivElement,
  MobileFormActionsProps
>(({ children, className, align = 'right', ...props }, ref) => {
  const isMobile = useIsMobile()
  
  const alignClasses = {
    left: 'justify-start',
    center: 'justify-center', 
    right: 'justify-end'
  }
  
  return (
    <div
      ref={ref}
      className={cn(
        "flex pt-6 border-t",
        isMobile 
          ? "flex-col space-y-3" 
          : `flex-row space-x-4 ${alignClasses[align]}`,
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
})
MobileFormActions.displayName = "MobileFormActions"

export {
  MobileFormLayout,
  MobileFormSection,
  MobileFormGrid,
  MobileFormActions,
}